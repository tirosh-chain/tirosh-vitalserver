import Contracts
import Foundation
import RuntimeControl

public enum RuntimeControlHTTPStatus: Int, Codable, Equatable, Sendable {
    case ok = 200
    case noContent = 204
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case notImplemented = 501
    case internalServerError = 500
}

public struct RuntimeControlHTTPRequest: Equatable, Sendable {
    public let method: RuntimeControlHTTPMethod
    public let path: String
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: RuntimeControlHTTPMethod,
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct RuntimeControlHTTPResponse: Equatable, Sendable {
    public let status: RuntimeControlHTTPStatus
    public let headers: [String: String]
    public let body: Data?

    public init(
        status: RuntimeControlHTTPStatus,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct RuntimeControlHTTPStreamResponse: Sendable {
    public let status: RuntimeControlHTTPStatus
    public let headers: [String: String]
    public let events: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>

    public init(
        status: RuntimeControlHTTPStatus,
        headers: [String: String],
        events: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>
    ) {
        self.status = status
        self.headers = headers
        self.events = events
    }
}

public enum RuntimeControlHTTPRouteResult: Sendable {
    case response(RuntimeControlHTTPResponse)
    case stream(RuntimeControlHTTPStreamResponse)
}

public struct RuntimeControlAPIStreamConfiguration: Equatable, Sendable {
    public let pollIntervalNanoseconds: UInt64
    public let heartbeatIntervalNanoseconds: UInt64

    public init(
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        heartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
    }
}

@MainActor
public protocol RuntimeControlAPIReadHandler {
    func loadCapabilities() async throws -> RuntimeControlCapabilities
    func loadStatus() async throws -> RuntimeStatus
    func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory
    func loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery) async throws -> RuntimeVitalRecorderActivityWindow
    func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory
    func loadHealthStatus() async throws -> RuntimeStatus
    func loadSettings() async throws -> RuntimeSettings
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() async throws -> RuntimeInstallInfo
    func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse
    func loadBackups() async throws -> [RuntimeBackup]
    func loadRedisBackups() async throws -> [RuntimeBackup]
    func loadRuntimeDataBackups() async throws -> [RuntimeBackup]
    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeControlCommandResponse
    func startRuntimeServices() async throws -> RuntimeControlCommandResponse
    func stopRuntimeServices() async throws -> RuntimeControlCommandResponse
    func repairRuntimeServices() async throws -> RuntimeControlCommandResponse
    func repairProxy() async throws -> RuntimeControlCommandResponse
    func repairDatastore() async throws -> RuntimeControlCommandResponse
    func repairVMDisk() async throws -> RuntimeControlCommandResponse
    func createRedisBackup() async throws -> RuntimeControlCommandResponse
    func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse
    func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse
    func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult
    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeControlCommandResponse
}

public extension RuntimeControlAPIReadHandler {
    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: nil,
            records: [],
            readError: "recorder activity window reader is unavailable"
        )
    }
}
