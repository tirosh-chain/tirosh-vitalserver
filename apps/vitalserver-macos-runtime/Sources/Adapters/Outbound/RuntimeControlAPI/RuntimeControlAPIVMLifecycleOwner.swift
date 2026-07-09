import Contracts
import Foundation
import RuntimeControl

public struct RuntimeControlAPIVMLifecycleOwner {
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

    public func loadVMLifecycleResource() throws -> RuntimeVMLifecycleResourceState {
        let response = try send(method: "GET", path: "/host/runtime/vm-lifecycle", body: nil)
        return try validated(decode(RuntimeVMLifecycleResourceState.self, from: response))
    }

    public func putVMLifecycleResource(
        _ document: RuntimeVMLifecycleDocument
    ) throws -> RuntimeVMLifecycleResourceState {
        struct Body: Encodable {
            let document: RuntimeVMLifecycleDocument
        }
        let response = try send(
            method: "PUT",
            path: "/host/runtime/vm-lifecycle",
            body: try encoder.encode(Body(document: document))
        )
        return try validated(decode(RuntimeVMLifecycleResourceState.self, from: response))
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

    private func validated(
        _ state: RuntimeVMLifecycleResourceState
    ) throws -> RuntimeVMLifecycleResourceState {
        switch state.state {
        case .loaded:
            guard state.document != nil else {
                throw RuntimeControlClientHTTPClientError.invalidVMLifecycleState(
                    "state=loaded has no VM lifecycle document"
                )
            }
        case .missing, .unavailable, .failed:
            break
        }
        return state
    }

    private func responseDetail(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "response body is not valid UTF-8"
    }
}
