import Foundation

@MainActor
public protocol RuntimeControlClient {
    var capabilities: RuntimeControlCapabilities { get }

    func loadSettings() -> RuntimeSettings
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult
    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult
    func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult
    func repairDatastore() async throws -> RuntimeCommandResult
    func startRuntimeServices() async throws -> RuntimeCommandResult
    func stopRuntimeServices() async throws -> RuntimeCommandResult
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() -> RuntimeInstallInfo
}

@MainActor
public protocol RuntimeHostClient {
    func loadBackups(latestBackupPath: String?) -> [RuntimeBackup]
    func updateBundleSummary(url: URL) -> String
    func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFilesFolder]
    func legacyCommandProgressLine() -> String?
    func createDirectory(at url: URL)
    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult
    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult
    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult
    func deleteBackup(url: URL) async throws -> RuntimeCommandResult
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}
