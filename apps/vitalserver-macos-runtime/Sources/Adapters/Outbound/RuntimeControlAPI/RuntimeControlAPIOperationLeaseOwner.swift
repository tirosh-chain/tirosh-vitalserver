import Application
import Contracts
import Errors
import Foundation
import RuntimeControl

public struct RuntimeControlClientHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol RuntimeControlClientHTTPClient: Sendable {
    func send(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse
}

public enum RuntimeControlClientHTTPClientError: Error, Equatable, CustomStringConvertible {
    case invalidBaseURL(String)
    case invalidRequestURL(baseURL: String, path: String)
    case invalidHTTPResponse(String)
    case transportFailed(url: String, reason: String)
    case requestFailed(statusCode: Int, detail: String)
    case decodeFailed(String)
    case invalidLeaseState(String)
    case invalidGuestAddressState(String)
    case invalidVMLifecycleState(String)

    public var description: String {
        switch self {
        case .invalidBaseURL(let baseURL):
            return "runtime control API base URL is invalid: \(baseURL)"
        case .invalidRequestURL(let baseURL, let path):
            return "runtime control API request URL is invalid baseURL=\(baseURL) path=\(path)"
        case .invalidHTTPResponse(let message):
            return message
        case .transportFailed(let url, let reason):
            return "runtime control API request failed url=\(url) reason=\(reason)"
        case .requestFailed(let statusCode, let detail):
            return "runtime control API request failed statusCode=\(statusCode) detail=\(detail)"
        case .decodeFailed(let message):
            return "runtime control API response decode failed: \(message)"
        case .invalidLeaseState(let message):
            return "runtime control API operation lease state is invalid: \(message)"
        case .invalidGuestAddressState(let message):
            return "runtime control API Guest address state is invalid: \(message)"
        case .invalidVMLifecycleState(let message):
            return "runtime control API VM lifecycle state is invalid: \(message)"
        }
    }
}

public struct URLSessionRuntimeControlClientHTTPClient: RuntimeControlClientHTTPClient {
    public init() {}

    public func send(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse {
        let resultBox = RuntimeControlClientHTTPResultBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                resultBox.store(.failure(RuntimeControlClientHTTPClientError.transportFailed(
                    url: request.url?.absoluteString ?? "unknown",
                    reason: Self.transportFailureReason(error)
                )))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                resultBox.store(.failure(RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                    "runtime control API returned a non-HTTP response"
                )))
                return
            }
            resultBox.store(.success(RuntimeControlClientHTTPResponse(
                statusCode: httpResponse.statusCode,
                data: data ?? Data()
            )))
        }
        task.resume()
        return try resultBox.wait()
    }

    private static func transportFailureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return error.localizedDescription
    }
}

public struct RuntimeControlAPIOperationLeaseOwner: RuntimeOperationLeaseOwner {
    private let baseURL: URL
    private let token: String
    private let headerName: String
    private let timeout: TimeInterval
    private let httpClient: any RuntimeControlClientHTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: String = RuntimeControlLocalAPIConnectionDefaults.baseURL(),
        token: String = RuntimeControlLocalAPIConnectionDefaults.token,
        headerName: String = RuntimeControlLocalAPIConnectionDefaults.headerName,
        timeout: TimeInterval = 5,
        httpClient: any RuntimeControlClientHTTPClient = URLSessionRuntimeControlClientHTTPClient(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw RuntimeControlClientHTTPClientError.invalidBaseURL(baseURL)
        }
        self.baseURL = url
        self.token = token
        self.headerName = headerName
        self.timeout = timeout
        self.httpClient = httpClient
        self.encoder = encoder
        self.decoder = decoder
    }

    public func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        do {
            let response = try send(method: "GET", path: "/runtime/operation-state", body: nil)
            let state = try decode(RuntimeOperationState.self, from: response).lease
            return try loadResult(from: state)
        } catch {
            return .failed(errorDescription(error))
        }
    }

    public func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        struct Body: Encodable {
            let document: RuntimeOperationLeaseDocument
        }
        let response = try send(
            method: "POST",
            path: "/host/runtime/operation-lease/acquire",
            body: try encoder.encode(Body(document: document))
        )
        let mutation = try decode(RuntimeOperationLeaseMutationResponse.self, from: response)
        guard mutation.operationId == document.operationId, mutation.state == .acquired else {
            throw RuntimeControlClientHTTPClientError.invalidLeaseState(
                "expected acquired operationId=\(document.operationId) actualOperationId=\(mutation.operationId) state=\(mutation.state.rawValue)"
            )
        }
    }

    public func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws {
        struct Body: Encodable {
            let operationId: String
            let heartbeatAt: String
            let expiresAt: String?
        }
        let response = try send(
            method: "POST",
            path: "/host/runtime/operation-lease/heartbeat",
            body: try encoder.encode(Body(
                operationId: operationId,
                heartbeatAt: heartbeatAt,
                expiresAt: expiresAt
            ))
        )
        let mutation = try decode(RuntimeOperationLeaseMutationResponse.self, from: response)
        guard mutation.operationId == operationId, mutation.state == .heartbeatRecorded else {
            throw RuntimeControlClientHTTPClientError.invalidLeaseState(
                "expected heartbeatRecorded operationId=\(operationId) actualOperationId=\(mutation.operationId) state=\(mutation.state.rawValue)"
            )
        }
    }

    public func release(operationId: String) throws {
        struct Body: Encodable {
            let operationId: String
        }
        let response = try send(
            method: "POST",
            path: "/host/runtime/operation-lease/release",
            body: try encoder.encode(Body(operationId: operationId))
        )
        let mutation = try decode(RuntimeOperationLeaseMutationResponse.self, from: response)
        guard mutation.operationId == operationId, mutation.state == .released else {
            throw RuntimeControlClientHTTPClientError.invalidLeaseState(
                "expected released operationId=\(operationId) actualOperationId=\(mutation.operationId) state=\(mutation.state.rawValue)"
            )
        }
    }

    private func send(method: String, path: String, body: Data?) throws -> RuntimeControlClientHTTPResponse {
        let request = try request(method: method, path: path, body: body)
        let response = try httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw RuntimeControlClientHTTPClientError.requestFailed(
                statusCode: response.statusCode,
                detail: responseDetail(response.data)
            )
        }
        return response
    }

    private func request(method: String, path: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: baseURL) else {
            throw RuntimeControlClientHTTPClientError.invalidRequestURL(baseURL: baseURL.absoluteString, path: path)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: headerName)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: RuntimeControlClientHTTPResponse) throws -> T {
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            throw RuntimeControlClientHTTPClientError.decodeFailed(error.localizedDescription)
        }
    }

    private func loadResult(from state: RuntimeOperationLeaseState) throws -> RuntimeOperationLeaseLoadResult {
        switch state.state {
        case .loaded, .stale:
            guard let document = state.document else {
                throw RuntimeControlClientHTTPClientError.invalidLeaseState(
                    "state=\(state.state.rawValue) has no lease document"
                )
            }
            return .loaded(document)
        case .unavailable:
            return .missing
        case .failed:
            return .failed(state.readError ?? "runtime control API reported failed operation lease read")
        }
    }

    private func responseDetail(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "response body is not valid UTF-8"
    }

    private func errorDescription(_ error: Error) -> String {
        String(describing: error)
    }
}

private final class RuntimeControlClientHTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<RuntimeControlClientHTTPResponse, Error>?

    func store(_ result: Result<RuntimeControlClientHTTPResponse, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> RuntimeControlClientHTTPResponse {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                "runtime control API did not produce a response"
            )
        }
        return try result.get()
    }
}
