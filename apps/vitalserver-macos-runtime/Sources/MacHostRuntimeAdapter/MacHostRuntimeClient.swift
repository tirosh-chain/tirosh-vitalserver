import Foundation
import Contracts
import RuntimeControl
import Core

@MainActor
public struct MacHostRuntimeClient: RuntimeControlClient, RuntimeHostClient {
    public let capabilities = RuntimeControlCapabilities()

    private let releaseInfo: RuntimeReleaseInfo
    private let statusReader: RuntimeStatusReading
    private let fileReader: RuntimeHostFileReading
    private let settingsReader: RuntimeSettingsReading
    private let commandWorker: MacHostRuntimeCommandWorker

    public init(
        releaseInfo: RuntimeReleaseInfo
    ) {
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: RuntimePaths()),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            commandWorker: MacHostRuntimeCommandWorker()
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        commandWorker: MacHostRuntimeCommandWorker
    ) {
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: RuntimePaths()),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            commandWorker: commandWorker
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        fileReader: RuntimeHostFileReading = SystemRuntimeHostFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        commandWorker: MacHostRuntimeCommandWorker = MacHostRuntimeCommandWorker()
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
        self.commandWorker = commandWorker
    }

    public func loadSettings() -> RuntimeSettings {
        settingsReader.load()
    }

    public func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        statusReader.loadStatus(settings: settings)
    }

    public func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        await statusReader.loadHealthStatus(settings: settings)
    }

    public func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        statusReader.loadRuntimeEvents(limit: limit)
    }

    public func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        statusReader.loadRuntimeEvents(query: query)
    }

    public func loadVitalDBObservation() -> VitalDBObservationDocument? {
        statusReader.loadVitalDBObservation()
    }

    public func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        statusReader.loadVitalDBRecorders()
    }

    public func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        statusReader.loadVitalDBRelationships()
    }

    public func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        try fileReader.backups(latestBackupPath: latestBackupPath)
    }

    public func loadRedisBackups() throws -> [RuntimeBackup] {
        try fileReader.redisBackups()
    }

    public func updateBundleSummary(url: URL) -> String {
        fileReader.updateBundleSummary(url: url)
    }

    public func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String {
        fileReader.logText(sourceID: sourceID, helperMessage: helperMessage, lineLimit: lineLimit)
    }

    public func loadLogText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) async -> String {
        await Task.detached(priority: .utility) {
            SystemRuntimeHostFileReader().logText(
                sourceID: sourceID,
                helperMessage: helperMessage,
                lineLimit: lineLimit
            )
        }.value
    }

    public func preferredLogsPath() -> String {
        fileReader.preferredLogsPath()
    }

    public func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        try fileReader.vitalFileFolders(root: root)
    }

    public func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.verifyUpdateBundle(url: url)
    }

    public func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult {
        try await commandWorker.uninstallRuntime(clean: clean)
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        try await commandWorker.applySettings(settings)
    }

    public func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.applyUpdateBundle(url: url)
    }

    public func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.rollbackRuntime(backupURL: backupURL)
    }

    public func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.deleteBackup(url: url)
    }

    public func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult {
        try await commandWorker.repairProxy(proxyPort: proxyPort)
    }

    public func repairDatastore() async throws -> RuntimeCommandResult {
        try await commandWorker.repairDatastore()
    }

    public func repairVMDisk() async throws -> RuntimeCommandResult {
        try await commandWorker.repairVMDisk()
    }

    public func repairRuntimeServices() async throws -> RuntimeCommandResult {
        try await commandWorker.repairRuntimeServices()
    }

    public func createRedisBackup() async throws -> RuntimeCommandResult {
        try await commandWorker.createRedisBackup()
    }

    public func startRuntimeServices() async throws -> RuntimeCommandResult {
        try await commandWorker.startRuntimeServices()
    }

    public func stopRuntimeServices() async throws -> RuntimeCommandResult {
        try await commandWorker.stopRuntimeServices()
    }

    public func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        try await commandWorker.exportLogs(to: destination)
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        releaseInfo
    }

    public func loadInstallInfo() -> RuntimeInstallInfo {
        RuntimeInstallInfo(
            appBundlePath: Bundle.main.bundlePath,
            packageIdentifier: RuntimeAdapterConstants.Product.packageIdentifier,
            runtimeHomePath: RuntimeAdapterConstants.Paths.vmHome,
            backupsPath: RuntimeAdapterConstants.Paths.backups,
            redisBackupsPath: RuntimeAdapterConstants.Paths.redisBackups
        )
    }

}

enum RuntimeClientError: LocalizedError {
    case missingLauncher
    case missingUninstaller
    case logExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingLauncher:
            return RuntimeAdapterConstants.StatusText.missingLauncher
        case .missingUninstaller:
            return RuntimeAdapterConstants.StatusText.missingUninstaller
        case .logExportFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? RuntimeAdapterConstants.StatusText.logExportFailed : trimmed
        }
    }
}
