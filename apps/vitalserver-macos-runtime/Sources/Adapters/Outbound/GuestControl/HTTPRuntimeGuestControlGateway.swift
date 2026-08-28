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
    func send(
        _ request: URLRequest,
        bodyFileURL: URL?
    ) throws -> RuntimeGuestControlHTTPResponse

    func sendAsync(
        _ request: URLRequest,
        bodyFileURL: URL?
    ) async throws -> RuntimeGuestControlHTTPResponse
}

public extension RuntimeGuestControlHTTPClient {
    func sendAsync(
        _ request: URLRequest,
        bodyFileURL: URL?
    ) async throws -> RuntimeGuestControlHTTPResponse {
        try send(request, bodyFileURL: bodyFileURL)
    }
}

public enum RuntimeGuestControlHTTPGatewayError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case invalidBaseURL(String)
    case invalidRequestURL(baseURL: String, path: String)
    case invalidHTTPResponse(String)
    case transportFailed(url: String, reason: String)
    case invalidVitalFileUpload(String)
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
        case .invalidVitalFileUpload(let message):
            return "guest control API vital file upload is invalid: \(message)"
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

    public func send(
        _ request: URLRequest,
        bodyFileURL: URL?
    ) throws -> RuntimeGuestControlHTTPResponse {
        let resultBox = RuntimeGuestControlHTTPResultBox()
        let completion: @Sendable (Data?, URLResponse?, Error?) -> Void = {
            data, response, error in
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
        let task: URLSessionTask
        if let bodyFileURL {
            task = URLSession.shared.uploadTask(
                with: request,
                fromFile: bodyFileURL,
                completionHandler: completion
            )
        } else {
            task = URLSession.shared.dataTask(
                with: request,
                completionHandler: completion
            )
        }
        task.resume()
        return try resultBox.wait()
    }

    public func sendAsync(
        _ request: URLRequest,
        bodyFileURL: URL?
    ) async throws -> RuntimeGuestControlHTTPResponse {
        do {
            let result: (Data, URLResponse)
            if let bodyFileURL {
                result = try await URLSession.shared.upload(
                    for: request,
                    fromFile: bodyFileURL
                )
            } else {
                result = try await URLSession.shared.data(for: request)
            }
            guard let httpResponse = result.1 as? HTTPURLResponse else {
                throw RuntimeGuestControlHTTPGatewayError.invalidHTTPResponse(
                    "guest control API returned a non-HTTP response"
                )
            }
            return RuntimeGuestControlHTTPResponse(
                statusCode: httpResponse.statusCode,
                data: result.0
            )
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw RuntimeGuestControlHTTPGatewayError.transportFailed(
                url: request.url?.absoluteString ?? "unknown",
                reason: Self.transportFailureReason(error)
            )
        }
    }

    private static func transportFailureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return error.localizedDescription
    }
}

private struct RuntimeGuestControlMultipartFile {
    private static let chunkBytes = 64 * 1024

    let directoryURL: URL
    let bodyURL: URL
    let sizeBytes: Int64

    static func build(
        sources: [RuntimeLabVitalFileUploadSource],
        boundary: String
    ) throws -> RuntimeGuestControlMultipartFile {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "vitalserver-runtime-upload-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false
            )
            let bodyURL = directoryURL.appendingPathComponent("multipart.body")
            guard FileManager.default.createFile(
                atPath: bodyURL.path,
                contents: nil
            ) else {
                throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                    "multipart staging file could not be created"
                )
            }
            let output = try FileHandle(forWritingTo: bodyURL)
            do {
                for source in sources {
                    try validateFileName(source.fileName)
                    try output.write(contentsOf: Data(
                        "--\(boundary)\r\n".utf8
                    ))
                    try output.write(contentsOf: Data((
                        "Content-Disposition: form-data; name=\"files\"; "
                        + "filename=\"\(source.fileName)\"\r\n"
                    ).utf8))
                    try output.write(contentsOf: Data(
                        "Content-Type: application/octet-stream\r\n\r\n".utf8
                    ))
                    try append(source, to: output)
                    try output.write(contentsOf: Data("\r\n".utf8))
                }
                try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
                try output.synchronize()
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
            let values = try bodyURL.resourceValues(forKeys: [.fileSizeKey])
            guard let sizeBytes = values.fileSize, sizeBytes >= 0 else {
                throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                    "multipart staging size is unavailable"
                )
            }
            return RuntimeGuestControlMultipartFile(
                directoryURL: directoryURL,
                bodyURL: bodyURL,
                sizeBytes: Int64(sizeBytes)
            )
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                "multipart staging failed: \(error.localizedDescription)"
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func validateFileName(_ fileName: String) throws {
        guard !fileName.isEmpty,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.contains("\""),
              !fileName.contains("\r"),
              !fileName.contains("\n")
        else {
            throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                "only basename file names are accepted: \(fileName)"
            )
        }
    }

    private static func append(
        _ source: RuntimeLabVitalFileUploadSource,
        to output: FileHandle
    ) throws {
        switch source.payload {
        case .bytes(let content):
            try output.write(contentsOf: content)
        case .file(let file):
            try append(file, named: source.fileName, to: output)
        }
    }

    private static func append(
        _ source: RuntimeLabVitalFileUploadFile,
        named fileName: String,
        to output: FileHandle
    ) throws {
        guard source.sizeBytes >= 0 else {
            throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                "source size is invalid: \(fileName)"
            )
        }
        let accessed = source.accessMode == .securityScoped
            ? source.url.startAccessingSecurityScopedResource()
            : false
        defer {
            if accessed {
                source.url.stopAccessingSecurityScopedResource()
            }
        }
        let values = try source.url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
        ])
        let actualSizeDescription = values.fileSize.map { String($0) }
            ?? "unavailable"
        guard values.isRegularFile == true,
              let actualSize = values.fileSize,
              Int64(actualSize) == source.sizeBytes else {
            throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                "source size changed before upload: \(fileName) "
                + "expected=\(source.sizeBytes) actual=\(actualSizeDescription)"
            )
        }
        let input = try FileHandle(forReadingFrom: source.url)
        defer { try? input.close() }
        var remaining = source.sizeBytes
        while remaining > 0 {
            let requested = Int(min(Int64(chunkBytes), remaining))
            guard let chunk = try input.read(upToCount: requested), !chunk.isEmpty else {
                throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                    "source ended before its declared size: \(fileName) "
                    + "remaining=\(remaining)"
                )
            }
            try output.write(contentsOf: chunk)
            remaining -= Int64(chunk.count)
        }
        if let extra = try input.read(upToCount: 1), !extra.isEmpty {
            throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                "source exceeds its declared size: \(fileName)"
            )
        }
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

private struct RuntimeGuestControlArchiveRestoreRequest: Encodable {
    let archive: String
}

private struct RuntimeGuestControlPostgresRestoreRequest: Encodable {
    let archive: String
    let restartRuntime: Bool
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
    RuntimeContainerImageSetGateway,
    RuntimeGuestReleaseGateway,
    RuntimeGuestProductLabGateway,
    RuntimeVitalDBGuestControlGateway
{
    private let baseURL: URL
    private let httpClient: any RuntimeGuestControlHTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let timeout: TimeInterval
    private let backupTimeout: TimeInterval

    public init(
        baseURL: String,
        httpClient: any RuntimeGuestControlHTTPClient = URLSessionRuntimeGuestControlHTTPClient(),
        timeout: TimeInterval = 5,
        backupTimeout: TimeInterval = 900
    ) throws {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else {
            throw RuntimeGuestControlHTTPGatewayError.invalidBaseURL(baseURL)
        }
        self.baseURL = url
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.timeout = timeout
        self.backupTimeout = backupTimeout
    }

    public func ready() throws -> RuntimeGuestControlReadiness {
        let response = try httpClient.send(
            request(method: "GET", path: "/ready", body: nil),
            bodyFileURL: nil
        )
        do {
            return try decoder.decode(RuntimeGuestControlReadiness.self, from: response.data)
        } catch {
            guard !(200..<300).contains(response.statusCode) else {
                throw RuntimeGuestControlHTTPGatewayError.decodeFailed(
                    runtimeGuestControlDecodingErrorDescription(error)
                )
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

    public func currentContainerImageSet() throws -> RuntimeContainerImageSetRead {
        let response = try httpClient.send(
            request(method: "GET", path: "/runtime/container-image-set", body: nil),
            bodyFileURL: nil
        )
        if response.statusCode == 503 {
            do {
                return try decoder.decode(RuntimeContainerImageSetRead.self, from: response.data)
            } catch {
                throw requestFailed(response)
            }
        }
        return try decode(RuntimeContainerImageSetRead.self, from: response)
    }

    public func applyContainerImageSet(
        _ request: RuntimeContainerImageSetMutationRequest
    ) throws -> RuntimeContainerImageSetOperation {
        try decode(
            RuntimeContainerImageSetOperation.self,
            method: "POST",
            path: "/runtime/container-image-set/apply",
            body: request
        )
    }

    public func rollbackContainerImageSet(
        _ request: RuntimeContainerImageSetMutationRequest
    ) throws -> RuntimeContainerImageSetOperation {
        try decode(
            RuntimeContainerImageSetOperation.self,
            method: "POST",
            path: "/runtime/container-image-set/rollback",
            body: request
        )
    }

    public func containerImageSetOperation(
        _ operationId: String
    ) throws -> RuntimeContainerImageSetOperation {
        try decode(
            RuntimeContainerImageSetOperation.self,
            method: "GET",
            path: "/runtime/container-image-set/operations/\(pathSegment(operationId))"
        )
    }

    public func activeGuestRelease() throws -> RuntimeGuestReleaseRead {
        let response = try httpClient.send(
            request(method: "GET", path: "/runtime/guest-runtime-release", body: nil),
            bodyFileURL: nil
        )
        if response.statusCode == 503 {
            do {
                return try decoder.decode(RuntimeGuestReleaseRead.self, from: response.data)
            } catch {
                throw requestFailed(response)
            }
        }
        return try decode(RuntimeGuestReleaseRead.self, from: response)
    }

    public func applyGuestRelease(
        _ request: RuntimeGuestReleaseMutationRequest
    ) throws -> RuntimeGuestReleaseOperation {
        try decode(
            RuntimeGuestReleaseOperation.self,
            method: "POST",
            path: "/runtime/guest-runtime-release/apply",
            body: request
        )
    }

    public func rollbackGuestRelease(
        _ request: RuntimeGuestReleaseMutationRequest
    ) throws -> RuntimeGuestReleaseOperation {
        try decode(
            RuntimeGuestReleaseOperation.self,
            method: "POST",
            path: "/runtime/guest-runtime-release/rollback",
            body: request
        )
    }

    public func guestReleaseOperation(
        _ operationId: String
    ) throws -> RuntimeGuestReleaseOperation {
        try decode(
            RuntimeGuestReleaseOperation.self,
            method: "GET",
            path: "/runtime/guest-runtime-release/operations/\(pathSegment(operationId))"
        )
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
            path: "/runtime/maintenance/redis-backup",
            timeoutInterval: backupTimeout
        )
    }

    public func createPostgresBackup() throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/postgres-backup",
            timeoutInterval: backupTimeout
        )
    }

    public func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool
    ) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/postgres-restore",
            body: RuntimeGuestControlPostgresRestoreRequest(
                archive: archive,
                restartRuntime: restartRuntime
            )
        )
    }

    public func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation {
        try decode(
            RuntimeGuestControlServiceOperation.self,
            method: "POST",
            path: "/runtime/maintenance/redis-restore",
            body: RuntimeGuestControlArchiveRestoreRequest(archive: archive)
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

    public func applyRecorderObservabilityExpectation(
        _ command: RuntimeRecorderObservabilityExpectationCommand
    ) throws -> RuntimeRecorderObservabilityExpectationReceipt {
        let encodedBody: Data
        do {
            encodedBody = try encoder.encode(command)
        } catch {
            throw RuntimeGuestControlHTTPGatewayError.decodeFailed(
                error.localizedDescription
            )
        }
        let response = try httpClient.send(
            request(
                method: "POST",
                path: "/runtime/vitaldb/recorders/\(pathSegment(command.vrcode))/observability/expectation",
                body: encodedBody
            ),
            bodyFileURL: nil
        )
        guard [200, 409, 422].contains(response.statusCode) else {
            throw requestFailed(response)
        }
        do {
            return try decoder.decode(
                RuntimeRecorderObservabilityExpectationReceipt.self,
                from: response.data
            )
        } catch {
            throw RuntimeGuestControlHTTPGatewayError.decodeFailed(
                runtimeGuestControlDecodingErrorDescription(error)
            )
        }
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

    public func vitalDBRecorderVitalFiles(_ vrcode: String) throws -> RuntimeVitalRecorderVitalFileHistory {
        try decode(
            RuntimeVitalRecorderVitalFileHistory.self,
            method: "GET",
            path: "/runtime/vitaldb/recorders/\(pathSegment(vrcode))/vital-files"
        )
    }

    public func recorderObservabilityDetail(
        _ vrcode: String
    ) throws -> RuntimeRecorderObservabilityDetail {
        try decode(
            RuntimeRecorderObservabilityDetail.self,
            method: "GET",
            path: "/runtime/vitaldb/recorders/\(pathSegment(vrcode))/observability"
        )
    }

    public func recorderObservabilityTimeline(
        _ query: RuntimeRecorderObservabilityTimelineQuery
    ) throws -> RuntimeRecorderObservabilityTimeline {
        try decode(
            RuntimeRecorderObservabilityTimeline.self,
            method: "GET",
            path: try recorderObservabilityHistoryPath(
                vrcode: query.vrcode,
                resource: "timeline",
                items: [
                    ("from", query.from),
                    ("until", query.until),
                    ("bucketSeconds", String(query.bucketSeconds)),
                ]
            )
        )
    }

    public func recorderObservabilityIncidents(
        _ query: RuntimeRecorderObservabilityIncidentQuery
    ) throws -> RuntimeRecorderObservabilityIncidents {
        var items = [
            ("from", query.from),
            ("until", query.until),
            ("limit", String(query.limit)),
        ]
        if let type = query.type {
            items.append(("type", type))
        }
        if let cursor = query.cursor {
            items.append(("cursor", cursor))
        }
        return try decode(
            RuntimeRecorderObservabilityIncidents.self,
            method: "GET",
            path: try recorderObservabilityHistoryPath(
                vrcode: query.vrcode,
                resource: "incidents",
                items: items
            )
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
            path: "/runtime/vitaldb/relationships?eventLimit=100"
        )
    }

    public func vitalDBRelationshipsAsync() async throws -> RuntimeGuestControlVitalDBRelationshipRead {
        try await decodeAsync(
            RuntimeGuestControlVitalDBRelationshipRead.self,
            method: "GET",
            path: "/runtime/vitaldb/relationships?eventLimit=100"
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

    public func finishLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse {
        try decode(
            RuntimeLabSessionResponse.self,
            method: "POST",
            path: "/runtime/lab/sessions/\(pathSegment(sessionId))/finish"
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

    public func uploadLabVitalFiles(
        _ sources: [RuntimeLabVitalFileUploadSource]
    ) throws -> RuntimeLabVitalFileLibraryUploadResponse {
        guard !sources.isEmpty else {
            throw RuntimeGuestControlHTTPGatewayError.invalidVitalFileUpload(
                "at least one .vital file is required"
            )
        }
        let boundary = "----tirosh-runtime-\(UUID().uuidString.lowercased())"
        let multipart = try RuntimeGuestControlMultipartFile.build(
            sources: sources,
            boundary: boundary
        )
        defer { multipart.remove() }

        var request = try request(
            method: "POST",
            path: "/runtime/lab/vital-files/upload",
            body: nil
        )
        request.timeoutInterval = max(timeout, 3_600)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            String(multipart.sizeBytes),
            forHTTPHeaderField: "Content-Length"
        )
        return try decode(
            RuntimeLabVitalFileLibraryUploadResponse.self,
            from: httpClient.send(request, bodyFileURL: multipart.bodyURL)
        )
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String
    ) throws -> T {
        let response = try httpClient.send(
            request(method: method, path: path, body: nil),
            bodyFileURL: nil
        )
        return try decode(type, from: response)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String,
        timeoutInterval: TimeInterval
    ) throws -> T {
        var request = try request(method: method, path: path, body: nil)
        request.timeoutInterval = timeoutInterval
        let response = try httpClient.send(request, bodyFileURL: nil)
        return try decode(type, from: response)
    }

    private func decodeAsync<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String
    ) async throws -> T {
        let response = try await httpClient.sendAsync(
            request(method: method, path: path, body: nil),
            bodyFileURL: nil
        )
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
        let response = try httpClient.send(
            request(method: method, path: path, body: encodedBody),
            bodyFileURL: nil
        )
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
            throw RuntimeGuestControlHTTPGatewayError.decodeFailed(
                runtimeGuestControlDecodingErrorDescription(error)
            )
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

    private func recorderObservabilityHistoryPath(
        vrcode: String,
        resource: String,
        items: [(String, String)]
    ) throws -> String {
        let query = try runtimeEventQueryPath(items.map { (name: $0.0, value: $0.1) })
            .dropFirst("/runtime/events?".count)
        return "/runtime/vitaldb/recorders/\(pathSegment(vrcode))"
            + "/observability/\(resource)?\(query)"
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

private func runtimeGuestControlDecodingErrorDescription(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
        return error.localizedDescription
    }
    switch decodingError {
    case .dataCorrupted(let context):
        return decodingIssueText(
            codingPath: context.codingPath,
            detail: context.debugDescription
        )
    case .keyNotFound(let key, let context):
        return decodingIssueText(
            codingPath: context.codingPath + [key],
            detail: "missing required key: \(context.debugDescription)"
        )
    case .typeMismatch(let type, let context):
        return decodingIssueText(
            codingPath: context.codingPath,
            detail: "expected \(type): \(context.debugDescription)"
        )
    case .valueNotFound(let type, let context):
        return decodingIssueText(
            codingPath: context.codingPath,
            detail: "missing \(type): \(context.debugDescription)"
        )
    @unknown default:
        return decodingError.localizedDescription
    }
}

private func decodingIssueText(codingPath: [any CodingKey], detail: String) -> String {
    let path = codingPath.reduce(into: "") { result, key in
        if let index = key.intValue {
            result += "[\(index)]"
        } else if result.isEmpty {
            result = key.stringValue
        } else {
            result += ".\(key.stringValue)"
        }
    }
    return path.isEmpty ? detail : "\(path): \(detail)"
}
