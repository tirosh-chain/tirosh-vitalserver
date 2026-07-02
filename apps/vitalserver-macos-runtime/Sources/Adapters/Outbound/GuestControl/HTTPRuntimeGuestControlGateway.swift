import Application
import Contracts
import Foundation
import RuntimeControl

public struct RuntimeGuestControlHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol RuntimeGuestControlHTTPClient: Sendable {
    func send(_ request: URLRequest) throws -> RuntimeGuestControlHTTPResponse
}

public enum RuntimeGuestControlHTTPGatewayError: Error, Equatable, CustomStringConvertible {
    case invalidBaseURL(String)
    case invalidRequestURL(baseURL: String, path: String)
    case invalidHTTPResponse(String)
    case transportFailed(url: String, reason: String)
    case requestFailed(statusCode: Int, code: String?, detail: String, availableServices: [String]?)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .invalidBaseURL(let baseURL):
            return "guest control API base URL is invalid: \(baseURL)"
        case .invalidRequestURL(let baseURL, let path):
            return "guest control API request URL is invalid baseURL=\(baseURL) path=\(path)"
        case .invalidHTTPResponse(let message):
            return message
        case .transportFailed(let url, let reason):
            return "guest control API request failed url=\(url) reason=\(reason)"
        case .requestFailed(let statusCode, let code, let detail, let availableServices):
            var message = "guest control API request failed statusCode=\(statusCode)"
            if let code {
                message += " code=\(code)"
            }
            message += " detail=\(detail)"
            if let availableServices {
                message += " availableServices=\(availableServices.joined(separator: ","))"
            }
            return message
        case .decodeFailed(let message):
            return "guest control API response decode failed: \(message)"
        }
    }
}

public struct URLSessionRuntimeGuestControlHTTPClient: RuntimeGuestControlHTTPClient {
    public init() {}

    public func send(_ request: URLRequest) throws -> RuntimeGuestControlHTTPResponse {
        let resultBox = RuntimeGuestControlHTTPResultBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                resultBox.store(.failure(RuntimeGuestControlHTTPGatewayError.transportFailed(
                    url: request.url?.absoluteString ?? "unknown",
                    reason: Self.transportFailureReason(error)
                )))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                resultBox.store(.failure(RuntimeGuestControlHTTPGatewayError.invalidHTTPResponse(
                    "guest control API returned a non-HTTP response"
                )))
                return
            }
            resultBox.store(.success(RuntimeGuestControlHTTPResponse(
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

private final class RuntimeGuestControlHTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<RuntimeGuestControlHTTPResponse, Error>?

    func store(_ result: Result<RuntimeGuestControlHTTPResponse, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> RuntimeGuestControlHTTPResponse {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw RuntimeGuestControlHTTPGatewayError.invalidHTTPResponse(
                "guest control API did not produce a response"
            )
        }
        return try result.get()
    }
}

private struct RuntimeGuestControlRedisRestoreRequest: Encodable {
    let archive: String
}

private struct RuntimeGuestControlUpdateActivationRequest: Encodable {
    let requestId: String
    let version: String
}

private struct RuntimeGuestControlUpdateShutdownRequest: Encodable {
    let requestId: String
    let version: String
}

public struct HTTPRuntimeGuestControlGateway: RuntimeGuestControlGateway, RuntimeGuestProductLabGateway {
    private let baseURL: URL
    private let httpClient: any RuntimeGuestControlHTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let timeout: TimeInterval

    public init(
        baseURL: String,
        httpClient: any RuntimeGuestControlHTTPClient = URLSessionRuntimeGuestControlHTTPClient(),
        timeout: TimeInterval = 5
    ) throws {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else {
            throw RuntimeGuestControlHTTPGatewayError.invalidBaseURL(baseURL)
        }
        self.baseURL = url
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.timeout = timeout
    }

    public func ready() throws -> RuntimeGuestControlReadiness {
        let response = try httpClient.send(request(method: "GET", path: "/ready", body: nil))
        do {
            return try decoder.decode(RuntimeGuestControlReadiness.self, from: response.data)
        } catch {
            guard !(200..<300).contains(response.statusCode) else {
                throw RuntimeGuestControlHTTPGatewayError.decodeFailed(error.localizedDescription)
            }
            throw requestFailed(response)
        }
    }

    public func capabilities() throws -> RuntimeGuestControlCapabilities {
        try decode(RuntimeGuestControlCapabilities.self, method: "GET", path: "/v1/capabilities")
    }

    public func listServices() throws -> RuntimeGuestControlServiceList {
        try decode(RuntimeGuestControlServiceList.self, method: "GET", path: "/v1/services")
    }

    public func stackStatus() throws -> RuntimeGuestControlStackStatus {
        try decode(RuntimeGuestControlStackStatus.self, method: "GET", path: "/v1/stack/status")
    }

    public func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        try decode(RuntimeGuestControlServiceStatus.self, method: "GET", path: "/v1/services/\(pathSegment(service))/status")
    }

    public func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/v1/services/\(pathSegment(service))/start")
    }

    public func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/v1/services/\(pathSegment(service))/stop")
    }

    public func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/v1/services/\(pathSegment(service))/restart")
    }

    public func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/v1/stack/reconcile")
    }

    public func createRedisBackup() throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/v1/maintenance/redis-backup"
        )
    }

    public func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/v1/maintenance/redis-restore",
            body: RuntimeGuestControlRedisRestoreRequest(archive: archive)
        )
    }

    public func repairDatastore() throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/v1/maintenance/datastore-repair"
        )
    }

    public func activateUpdate(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/v1/maintenance/update-activation",
            body: RuntimeGuestControlUpdateActivationRequest(
                requestId: requestId,
                version: version
            )
        )
    }

    public func prepareUpdateShutdown(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/v1/maintenance/update-shutdown",
            body: RuntimeGuestControlUpdateShutdownRequest(
                requestId: requestId,
                version: version
            )
        )
    }

    public func requestGuestPoweroff() throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/v1/maintenance/guest-poweroff"
        )
    }

    public func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "GET", path: "/v1/operations/\(operationId)")
    }

    public func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        try decode(
            RuntimeGuestControlVitalDBObservationRead.self,
            method: "GET",
            path: "/v1/vitaldb/observations/latest"
        )
    }

    public func vitalDBRecorders() throws -> RuntimeGuestControlVitalDBRecorderRead {
        try decode(
            RuntimeGuestControlVitalDBRecorderRead.self,
            method: "GET",
            path: "/v1/vitaldb/recorders"
        )
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead {
        try decode(
            RuntimeGuestControlVitalDBRecorderRead.self,
            method: "POST",
            path: "/v1/vitaldb/recorders/hide",
            body: request
        )
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead {
        try decode(
            RuntimeGuestControlVitalDBRecorderRead.self,
            method: "POST",
            path: "/v1/vitaldb/recorders/unhide",
            body: request
        )
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead {
        try decode(
            RuntimeGuestControlVitalDBRecorderRead.self,
            method: "POST",
            path: "/v1/vitaldb/recorders/delete",
            body: request
        )
    }

    public func vitalDBRecorderActivity(_ vrcode: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead {
        try decode(
            RuntimeGuestControlVitalDBRecorderActivityRead.self,
            method: "GET",
            path: "/v1/vitaldb/recorders/\(pathSegment(vrcode))/activity"
        )
    }

    public func vitalDBBeds() throws -> RuntimeGuestControlVitalDBBedRead {
        try decode(
            RuntimeGuestControlVitalDBBedRead.self,
            method: "GET",
            path: "/v1/vitaldb/beds"
        )
    }

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead {
        try decode(
            RuntimeGuestControlVitalDBBedRead.self,
            method: "POST",
            path: "/v1/vitaldb/beds/hide",
            body: request
        )
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead {
        try decode(
            RuntimeGuestControlVitalDBBedRead.self,
            method: "POST",
            path: "/v1/vitaldb/beds/unhide",
            body: request
        )
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead {
        try decode(
            RuntimeGuestControlVitalDBBedRead.self,
            method: "POST",
            path: "/v1/vitaldb/beds/delete",
            body: request
        )
    }

    public func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead {
        try decode(
            RuntimeGuestControlVitalDBRelationshipRead.self,
            method: "GET",
            path: "/v1/vitaldb/relationships"
        )
    }

    public func recorderIngressStatus() throws -> RuntimeRecorderIngressStatusReadResult {
        try decode(
            RuntimeRecorderIngressStatusReadResult.self,
            method: "GET",
            path: "/v1/recorder-ingress/status"
        )
    }

    public func labScenarios() throws -> RuntimeLabScenarioList {
        try decode(RuntimeLabScenarioList.self, method: "GET", path: "/v1/lab/scenarios")
    }

    public func labVitalFiles() throws -> RuntimeLabVitalFileList {
        try decode(RuntimeLabVitalFileList.self, method: "GET", path: "/v1/lab/vital-files")
    }

    public func labBeds() throws -> RuntimeLabBedList {
        try decode(RuntimeLabBedList.self, method: "GET", path: "/v1/lab/beds")
    }

    public func labRecorders() throws -> RuntimeLabRecorderList {
        try decode(RuntimeLabRecorderList.self, method: "GET", path: "/v1/lab/recorders")
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) throws -> RuntimeLabBedList {
        try decode(
            RuntimeLabBedList.self,
            method: "POST",
            path: "/v1/lab/beds/create",
            body: request
        )
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) throws -> RuntimeLabBedList {
        try decode(
            RuntimeLabBedList.self,
            method: "POST",
            path: "/v1/lab/beds/delete",
            body: request
        )
    }

    public func resetLabBeds() throws -> RuntimeLabBedList {
        try decode(
            RuntimeLabBedList.self,
            method: "POST",
            path: "/v1/lab/beds/reset"
        )
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) throws -> RuntimeLabRecorderList {
        try decode(
            RuntimeLabRecorderList.self,
            method: "POST",
            path: "/v1/lab/recorders/create",
            body: request
        )
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) throws -> RuntimeLabRecorderList {
        try decode(
            RuntimeLabRecorderList.self,
            method: "POST",
            path: "/v1/lab/recorders/delete",
            body: request
        )
    }

    public func resetLabRecorders() throws -> RuntimeLabRecorderList {
        try decode(
            RuntimeLabRecorderList.self,
            method: "POST",
            path: "/v1/lab/recorders/reset"
        )
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/v1/lab/sessions",
            body: request
        )
    }

    public func labSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "GET",
            path: "/v1/lab/sessions/\(pathSegment(sessionId))"
        )
    }

    public func startLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/v1/lab/sessions/\(pathSegment(sessionId))/start"
        )
    }

    public func stopLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/v1/lab/sessions/\(pathSegment(sessionId))/stop"
        )
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/v1/lab/vital-files/replay",
            body: request
        )
    }

    public func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) throws -> RuntimeLabVitalFileUploadResponse {
        try decode(
            RuntimeLabVitalFileUploadResponse.self,
            method: "POST",
            path: "/v1/lab/vital-files/upload",
            body: request
        )
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String
    ) throws -> T {
        let response = try httpClient.send(request(method: method, path: path, body: nil))
        return try decode(type, from: response)
    }

    private func decode<T: Decodable, Body: Encodable>(
        _ type: T.Type,
        method: String,
        path: String,
        body: Body
    ) throws -> T {
        let encodedBody: Data
        do {
            encodedBody = try encoder.encode(body)
        } catch {
            throw RuntimeGuestControlHTTPGatewayError.decodeFailed(error.localizedDescription)
        }
        let response = try httpClient.send(request(method: method, path: path, body: encodedBody))
        return try decode(type, from: response)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from response: RuntimeGuestControlHTTPResponse
    ) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            throw requestFailed(response)
        }
        do {
            return try decoder.decode(type, from: response.data)
        } catch {
            throw RuntimeGuestControlHTTPGatewayError.decodeFailed(error.localizedDescription)
        }
    }

    private func request(method: String, path: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: baseURL) else {
            throw RuntimeGuestControlHTTPGatewayError.invalidRequestURL(baseURL: baseURL.absoluteString, path: path)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func requestFailed(_ response: RuntimeGuestControlHTTPResponse) -> RuntimeGuestControlHTTPGatewayError {
        if let document = try? decoder.decode(RuntimeGuestControlErrorDocument.self, from: response.data) {
            return .requestFailed(
                statusCode: response.statusCode,
                code: document.code,
                detail: document.detail,
                availableServices: document.availableServices
            )
        }
        let detail = String(data: response.data, encoding: .utf8) ?? "response body is not valid UTF-8"
        return .requestFailed(
            statusCode: response.statusCode,
            code: nil,
            detail: detail,
            availableServices: nil
        )
    }
}
