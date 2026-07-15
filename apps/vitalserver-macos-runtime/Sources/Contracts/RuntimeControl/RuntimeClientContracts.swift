import Foundation
import Contracts
import Errors

public enum RuntimeControlClientUnsupportedError: LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let capability):
            return "runtime control client capability is unavailable: \(capability)"
        }
    }
}

public enum RuntimeUninstallMode: String, Codable, Equatable, Sendable {
    case standard
    case clean
    case forceCleanUninstaller

    public var clean: Bool {
        self != .standard
    }

    public var forceClean: Bool {
        self == .forceCleanUninstaller
    }
}

@MainActor
public protocol RuntimeControlClient {
    var capabilities: RuntimeControlCapabilities { get }

    func loadSettings() -> RuntimeSettings
    func loadPlatformState(settings: RuntimeSettings) -> PlatformState
    func loadOperationState() -> PlatformOperationState
    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBBeds() -> RuntimeVitalBedHistory
    func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory
    func loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery) -> RuntimeVitalRecorderActivityWindow
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult
    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult
    func restartVMRuntime(applying settings: RuntimeSettings) async throws -> RuntimeCommandResult
    func loadLabScenarios() async throws -> RuntimeLabScenarioList
    func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList
    func loadLabBeds() async throws -> RuntimeLabBedList
    func loadLabRecorders() async throws -> RuntimeLabRecorderList
    func loadLabSessions() async throws -> RuntimeLabSessionList
    func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList
    func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList
    func resetLabBeds() async throws -> RuntimeLabBedList
    func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList
    func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList
    func resetLabRecorders() async throws -> RuntimeLabRecorderList
    func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory
    func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory
    func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory
    func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory
    func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory
    func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory
    func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse
    func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func finishLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func startLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse
    func stopLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse
    func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse
    func uploadLabVitalFiles(_ sources: [RuntimeLabVitalFileUploadSource]) async throws -> RuntimeLabVitalFileLibraryUploadResponse
    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus
    func runtimeCapabilities() async throws -> RuntimeCapabilities
    func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead
    func applyRuntimeProductSettings(_ settings: GuestRuntimeSettingsDocument) async throws -> RuntimeGuestControlServiceOperation
    func applyRuntimeAdminPassword(_ password: String) async throws -> RuntimeGuestControlServiceOperation
    func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead
    func applyRuntimeRedisRelaySettings(_ settings: RuntimeRedisRelaySettingsApplyRequest) async throws -> RuntimeGuestControlServiceOperation
    func loadRuntimeOperationEvents(query: RuntimeOperationEventQuery) async throws -> RuntimeOperationEventHistory
    func listGuestServices() async throws -> RuntimeGuestControlServiceList
    func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus
    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource
    func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult
    func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation
    func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation
    func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() -> RuntimeInstallInfo
}

public extension RuntimeControlClient {
    func runtimeCapabilities() async throws -> RuntimeCapabilities {
        throw RuntimeControlClientUnsupportedError.unavailable("runtime-capabilities")
    }

    func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        throw RuntimeControlClientUnsupportedError.unavailable("settings:get")
    }

    func applyRuntimeProductSettings(
        _ settings: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("settings:apply")
    }

    func applyRuntimeAdminPassword(_: String) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("admin-password:apply")
    }

    func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        throw RuntimeControlClientUnsupportedError.unavailable("redis-relay:settings:get")
    }

    func applyRuntimeRedisRelaySettings(_: RuntimeRedisRelaySettingsApplyRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("redis-relay:settings:apply")
    }

    func loadRuntimeOperationEvents(
        query _: RuntimeOperationEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("events:get")
    }

    func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        RuntimeRedisRelayStatusReadResult(
            readState: .readFailed,
            document: nil,
            readError: "Redis Relay status owner is unavailable"
        )
    }

    func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func loadVitalDBBeds() -> RuntimeVitalBedHistory {
        .failed(readError: "vitaldb-beds reader is unavailable")
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: nil,
            records: [],
            readError: "recorder activity window reader is unavailable"
        )
    }

    func hideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("vitaldb-recorders-hide")
    }

    func unhideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("vitaldb-recorders-unhide")
    }

    func deleteVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("vitaldb-recorders-delete")
    }

    func hideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("vitaldb-beds-hide")
    }

    func unhideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("vitaldb-beds-unhide")
    }

    func deleteVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("vitaldb-beds-delete")
    }

    func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-service-start")
    }

    func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-service-stop")
    }

    func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-service-restart")
    }

    func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-services-list")
    }

    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-stack-status")
    }

    func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-service-status")
    }

    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-service-resource")
    }

    func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        RuntimeLabScenarioList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        RuntimeLabVitalFileList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabBeds() async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func resetLabBeds() async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabSessions() async throws -> RuntimeLabSessionList {
        RuntimeLabSessionList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func finishLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func startLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        RuntimeLabRecorderResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func stopLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        RuntimeLabRecorderResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func uploadLabVitalFiles(_ sources: [RuntimeLabVitalFileUploadSource]) async throws -> RuntimeLabVitalFileLibraryUploadResponse {
        throw RuntimeControlClientUnsupportedError.unavailable("lab-vital-files-upload")
    }

}

public enum RuntimeHostTextMissingReason: Equatable, Sendable {
    case noData
    case message(String)
}

public extension RuntimeControlClient {
    func restartVMRuntime(applying settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        throw RuntimeControlClientUnsupportedError.unavailable("restart-vm-runtime-after-settings-apply")
    }
}

public enum RuntimeHostTextReadResult: Equatable, Sendable {
    case loaded(String)
    case loadedWithIssue(text: String, issue: String)
    case missing(RuntimeHostTextMissingReason)
    case failed(String)
}

@MainActor
public protocol RuntimeHostClient {
    func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup]
    func loadRedisBackups() throws -> [RuntimeBackup]
    func loadRuntimeDataBackups() throws -> [RuntimeBackup]
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult
    func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder]
    func repairProxy() async throws -> RuntimeCommandResult
    func repairDatastore() async throws -> RuntimeCommandResult
    func repairVMDisk() async throws -> RuntimeCommandResult
    func repairRuntimeServices() async throws -> RuntimeCommandResult
    func controlRuntimeProvider(_ action: RuntimeProviderCommandAction) async throws -> RuntimeCommandResult
    func createRedisBackup() async throws -> RuntimeCommandResult
    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult
    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult
    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult
    func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult
    func createRuntimeDataBackup() async throws -> RuntimeCommandResult
    func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult
    func deleteBackup(url: URL) async throws -> RuntimeCommandResult
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
    func acquireOperationLease(_ document: RuntimeOperationLeaseDocument) async throws -> RuntimeOperationLeaseMutationResponse
    func heartbeatOperationLease(operationId: String, heartbeatAt: String, expiresAt: String?) async throws -> RuntimeOperationLeaseMutationResponse
    func releaseOperationLease(operationId: String) async throws -> RuntimeOperationLeaseMutationResponse
}

public extension RuntimeHostClient {
    func controlRuntimeProvider(_ action: RuntimeProviderCommandAction) async throws -> RuntimeCommandResult {
        throw RuntimeControlClientUnsupportedError.unavailable("runtime-provider-\(action.rawValue)")
    }

    func acquireOperationLease(
        _ document: RuntimeOperationLeaseDocument
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        throw RuntimeControlClientUnsupportedError.unavailable("operation-lease-acquire")
    }

    func heartbeatOperationLease(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        throw RuntimeControlClientUnsupportedError.unavailable("operation-lease-heartbeat")
    }

    func releaseOperationLease(
        operationId: String
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        throw RuntimeControlClientUnsupportedError.unavailable("operation-lease-release")
    }
}
