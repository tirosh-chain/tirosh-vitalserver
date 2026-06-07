import Foundation
import Contracts
import Errors

@MainActor
public protocol RuntimeControlClient {
    var capabilities: RuntimeControlCapabilities { get }

    func loadSettings() -> RuntimeSettings
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
    func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult
    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult
    func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult
    func repairDatastore() async throws -> RuntimeCommandResult
    func repairVMDisk() async throws -> RuntimeCommandResult
    func repairRuntimeServices() async throws -> RuntimeCommandResult
    func createRedisBackup() async throws -> RuntimeCommandResult
    func startRuntimeServices() async throws -> RuntimeCommandResult
    func stopRuntimeServices() async throws -> RuntimeCommandResult
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() -> RuntimeInstallInfo
}

public enum RuntimeHostTextMissingReason: Equatable, Sendable {
    case noData
    case message(String)
}

public enum RuntimeHostTextReadResult: Equatable, Sendable {
    case loaded(String)
    case missing(RuntimeHostTextMissingReason)
    case failed(String)
}

@MainActor
public protocol RuntimeHostClient {
    func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup]
    func loadRedisBackups() throws -> [RuntimeBackup]
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult
    func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder]
    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult
    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult
    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult
    func deleteBackup(url: URL) async throws -> RuntimeCommandResult
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}
