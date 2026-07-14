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

public enum RuntimeGuestControlHTTPGatewayError: Error, Equatable, CustomStringConvertible, LocalizedError {
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

    public var errorDescription: String? { description }
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

public struct HTTPRuntimeGuestControlGateway: RuntimeGuestControlGateway,
    RuntimeGuestProductLabGateway,
    RuntimeVitalDBGuestControlGateway
{
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
        try decode(RuntimeGuestControlCapabilities.self, method: "GET", path: "/runtime/capabilities")
    }

    public func runtimeSettings() throws -> RuntimeProductSettingsRead {
        try decode(RuntimeProductSettingsRead.self, method: "GET", path: "/runtime/settings")
    }

    public func applyRuntimeSettings(
        _ settings: GuestRuntimeSettingsDocument
    ) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "PUT",
            path: "/runtime/settings",
            body: RuntimeApplyProductSettingsRequest(settings: settings)
        )
    }

    public func applyAdminPassword(_ password: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/admin-password",
            body: RuntimeAdminPasswordRequest(password: password)
        )
    }

    public func redisRelaySettings() throws -> RuntimeRedisRelaySettingsRead {
        try decode(
            RuntimeRedisRelaySettingsRead.self,
            method: "GET",
            path: "/runtime/redis-relay/settings"
        )
    }

    public func applyRedisRelaySettings(
        _ settings: RuntimeRedisRelaySettingsApplyRequest
    ) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "PUT",
            path: "/runtime/redis-relay/settings",
            body: settings
        )
    }

    public func runtimeEvents(query: RuntimeOperationEventQuery) throws -> RuntimeOperationEventHistory {
        var items = [(name: "limit", value: String(query.limit))]
        if let eventType = query.eventType {
            items.append((name: "type", value: eventType.rawValue))
        }
        if let since = query.since {
            items.append((name: "since", value: since))
        }
        if let cursor = query.cursor {
            items.append((name: "cursor", value: cursor))
        }
        let path = try runtimeEventQueryPath(items)
        do {
            return try decode(RuntimeOperationEventHistory.self, method: "GET", path: path)
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            switch error {
            case .requestFailed(
                statusCode: 400,
                code: "queryParameterInvalid",
                detail: let detail,
                availableServices: _
            ):
                throw RuntimeGuestOperationEventQueryRejectedError(detail: detail)
            case .requestFailed(
                statusCode: 503,
                code: _,
                detail: let detail,
                availableServices: _
            ):
                throw RuntimeGuestOperationEventHistoryUnavailableError(detail: detail)
            default:
                throw error
            }
        }
    }

    public func listServices() throws -> RuntimeGuestControlServiceList {
        try decode(RuntimeGuestControlServiceList.self, method: "GET", path: "/runtime/services")
    }

    public func stackStatus() throws -> RuntimeGuestControlStackStatus {
        try decode(RuntimeGuestControlStackStatus.self, method: "GET", path: "/runtime/stack")
    }

    public func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        try decode(RuntimeGuestControlServiceStatus.self, method: "GET", path: "/runtime/services/\(pathSegment(service))/status")
    }

    public func serviceResource(_ service: String) throws -> RuntimeGuestServiceResource {
        try decode(RuntimeGuestServiceResource.self, method: "GET", path: "/runtime/services/\(pathSegment(service))/resource")
    }

    public func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/runtime/services/\(pathSegment(service))/start")
    }

    public func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/runtime/services/\(pathSegment(service))/stop")
    }

    public func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/runtime/services/\(pathSegment(service))/restart")
    }

    public func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "POST", path: "/runtime/stack/reconcile")
    }

    public func createRedisBackup() throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/redis-backup"
        )
    }

    public func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/redis-restore",
            body: RuntimeGuestControlRedisRestoreRequest(archive: archive)
        )
    }

    public func repairDatastore() throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/datastore/repair"
        )
    }

    public func activateUpdate(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/update-activation",
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
            path: "/runtime/maintenance/update-shutdown",
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
            path: "/runtime/maintenance/guest-poweroff"
        )
    }

    public func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(RuntimeGuestControlServiceOperation.self, method: "GET", path: "/runtime/operations/\(operationId)")
    }

    public func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        try decode(
            RuntimeGuestControlVitalDBObservationRead.self,
            method: "GET",
            path: "/runtime/vitaldb/observations/latest"
        )
    }

    public func vitalDBRecorders() throws -> RuntimeVitalRecorderHistory {
        try decode(
            RuntimeVitalRecorderHistory.self,
            method: "GET",
            path: "/runtime/vitaldb/recorders"
        )
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeVitalRecorderHistory {
        try decode(
            RuntimeVitalRecorderHistory.self,
            method: "POST",
            path: "/runtime/vitaldb/recorders/hide",
            body: request
        )
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeVitalRecorderHistory {
        try decode(
            RuntimeVitalRecorderHistory.self,
            method: "POST",
            path: "/runtime/vitaldb/recorders/unhide",
            body: request
        )
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeVitalRecorderHistory {
        try decode(
            RuntimeVitalRecorderHistory.self,
            method: "POST",
            path: "/runtime/vitaldb/recorders/delete",
            body: request
        )
    }

    public func vitalDBRecorderActivity(_ vrcode: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead {
        try decode(
            RuntimeGuestControlVitalDBRecorderActivityRead.self,
            method: "GET",
            path: "/runtime/vitaldb/recorders/\(pathSegment(vrcode))/activity"
        )
    }

    public func vitalDBBeds() throws -> RuntimeVitalBedHistory {
        try decode(
            RuntimeVitalBedHistory.self,
            method: "GET",
            path: "/runtime/vitaldb/beds"
        )
    }

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeVitalBedHistory {
        try decode(
            RuntimeVitalBedHistory.self,
            method: "POST",
            path: "/runtime/vitaldb/beds/hide",
            body: request
        )
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeVitalBedHistory {
        try decode(
            RuntimeVitalBedHistory.self,
            method: "POST",
            path: "/runtime/vitaldb/beds/unhide",
            body: request
        )
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeVitalBedHistory {
        try decode(
            RuntimeVitalBedHistory.self,
            method: "POST",
            path: "/runtime/vitaldb/beds/delete",
            body: request
        )
    }

    public func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead {
        try decode(
            RuntimeGuestControlVitalDBRelationshipRead.self,
            method: "GET",
            path: "/runtime/vitaldb/relationships"
        )
    }

    public func recorderIngressStatus() throws -> RuntimeRecorderIngressStatusReadResult {
        try decode(
            RuntimeRecorderIngressStatusReadResult.self,
            method: "GET",
            path: "/runtime/recorder-ingress/status"
        )
    }

    public func redisRelayStatus() throws -> RuntimeRedisRelayStatusReadResult {
        try decode(
            RuntimeRedisRelayStatusReadResult.self,
            method: "GET",
            path: "/runtime/redis-relay/status"
        )
    }

    public func labScenarios() throws -> RuntimeLabScenarioList {
        try decode(RuntimeLabScenarioList.self, method: "GET", path: "/runtime/lab/scenarios")
    }

    public func labVitalFiles() throws -> RuntimeLabVitalFileList {
        try decode(RuntimeLabVitalFileList.self, method: "GET", path: "/runtime/lab/vital-files")
    }

    public func labBeds() throws -> RuntimeLabBedList {
        try decode(RuntimeLabBedList.self, method: "GET", path: "/runtime/lab/beds")
    }

    public func labRecorders() throws -> RuntimeLabRecorderList {
        try decode(RuntimeLabRecorderList.self, method: "GET", path: "/runtime/lab/recorders")
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) throws -> RuntimeLabBedList {
        try decode(
            RuntimeLabBedList.self,
            method: "POST",
            path: "/runtime/lab/beds/create",
            body: request
        )
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) throws -> RuntimeLabBedList {
        try decode(
            RuntimeLabBedList.self,
            method: "POST",
            path: "/runtime/lab/beds/delete",
            body: request
        )
    }

    public func resetLabBeds() throws -> RuntimeLabBedList {
        try decode(
            RuntimeLabBedList.self,
            method: "POST",
            path: "/runtime/lab/beds/reset"
        )
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) throws -> RuntimeLabRecorderList {
        try decode(
            RuntimeLabRecorderList.self,
            method: "POST",
            path: "/runtime/lab/recorders/create",
            body: request
        )
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) throws -> RuntimeLabRecorderList {
        try decode(
            RuntimeLabRecorderList.self,
            method: "POST",
            path: "/runtime/lab/recorders/delete",
            body: request
        )
    }

    public func resetLabRecorders() throws -> RuntimeLabRecorderList {
        try decode(
            RuntimeLabRecorderList.self,
            method: "POST",
            path: "/runtime/lab/recorders/reset"
        )
    }

    public func labSessions() throws -> RuntimeLabSessionList {
        try decode(
            RuntimeLabSessionList.self,
            method: "GET",
            path: "/runtime/lab/sessions"
        )
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/runtime/lab/sessions",
            body: request
        )
    }

    public func labSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "GET",
            path: "/runtime/lab/sessions/\(pathSegment(sessionId))"
        )
    }

    public func startLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/runtime/lab/sessions/\(pathSegment(sessionId))/start"
        )
    }

    public func stopLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/runtime/lab/sessions/\(pathSegment(sessionId))/stop"
        )
    }

    public func startLabRecorder(sessionId: String, recorderId: String) throws -> RuntimeLabRecorderResponse {
        try decode(
            RuntimeLabRecorderResponse.self,
            method: "POST",
            path: "/runtime/lab/sessions/\(pathSegment(sessionId))/recorders/\(pathSegment(recorderId))/start"
        )
    }

    public func stopLabRecorder(sessionId: String, recorderId: String) throws -> RuntimeLabRecorderResponse {
        try decode(
            RuntimeLabRecorderResponse.self,
            method: "POST",
            path: "/runtime/lab/sessions/\(pathSegment(sessionId))/recorders/\(pathSegment(recorderId))/stop"
        )
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/runtime/lab/vital-files/replay",
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

    private func runtimeEventQueryPath(
        _ items: [(name: String, value: String)]
    ) throws -> String {
        let encodedItems = try items.map { item -> String in
            guard let encodedValue = item.value.addingPercentEncoding(
                withAllowedCharacters: Self.runtimeEventQueryValueAllowedCharacters
            ) else {
                throw RuntimeGuestControlHTTPGatewayError.invalidRequestURL(
                    baseURL: baseURL.absoluteString,
                    path: "/runtime/events"
                )
            }
            return "\(item.name)=\(encodedValue)"
        }
        return "/runtime/events?\(encodedItems.joined(separator: "&"))"
    }

    private static let runtimeEventQueryValueAllowedCharacters: CharacterSet = {
        var characters = CharacterSet.alphanumerics
        characters.insert(charactersIn: "-._~")
        return characters
    }()

    private func requestFailed(_ response: RuntimeGuestControlHTTPResponse) -> Error {
        if let document = try? decoder.decode(RuntimeGuestControlErrorDocument.self, from: response.data) {
            if response.statusCode == 409, document.code == "operationInProgress" {
                return RuntimeControlOperationInProgressError(message: document.detail)
            }
            return RuntimeGuestControlHTTPGatewayError.requestFailed(
                statusCode: response.statusCode,
                code: document.code,
                detail: document.detail,
                availableServices: document.availableServices
            )
        }
        let detail = String(data: response.data, encoding: .utf8) ?? "response body is not valid UTF-8"
        return RuntimeGuestControlHTTPGatewayError.requestFailed(
            statusCode: response.statusCode,
            code: nil,
            detail: detail,
            availableServices: nil
        )
    }
}
