import Foundation
import Contracts
import RuntimeControl
import Application
import Domain
import Errors

@MainActor
public struct MacRuntimeControlClient: RuntimeControlClient, RuntimeHostClient {
    public let capabilities = RuntimeControlCapabilities()

    private let releaseInfo: RuntimeReleaseInfo
    private let statusReader: RuntimeStatusReading
    private let observabilityReader: RuntimeObservabilityReading
    private let fileReader: RuntimeHostFileReading
    private let settingsReader: RuntimeSettingsReading
    private let commandWorker: MacRuntimeControlCommandWorker

    public init(
        releaseInfo: RuntimeReleaseInfo
    ) {
        let paths = RuntimePaths()
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: paths),
            observabilityReader: SystemRuntimeObservabilityReader.live(paths: paths),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            commandWorker: MacRuntimeControlCommandWorker()
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        commandWorker: MacRuntimeControlCommandWorker
    ) {
        let paths = RuntimePaths()
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: paths),
            observabilityReader: SystemRuntimeObservabilityReader.live(paths: paths),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            commandWorker: commandWorker
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        observabilityReader: RuntimeObservabilityReading = SystemRuntimeObservabilityReader.live(paths: RuntimePaths()),
        fileReader: RuntimeHostFileReading = SystemRuntimeHostFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        commandWorker: MacRuntimeControlCommandWorker = MacRuntimeControlCommandWorker()
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.observabilityReader = observabilityReader
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
        observabilityReader.loadRuntimeEvents(limit: limit)
    }

    public func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        observabilityReader.loadRuntimeEvents(query: query)
    }

    public func loadVitalDBObservation() -> VitalDBObservationDocument? {
        observabilityReader.loadVitalDBObservation()
    }

    public func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        observabilityReader.loadVitalDBObservationSnapshot()
    }

    public func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        observabilityReader.loadVitalDBRecorders()
    }

    public func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        observabilityReader.loadVitalDBRelationships()
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
            packageIdentifier: RuntimeControlClientConstants.Product.packageIdentifier,
            runtimeHomePath: RuntimeControlClientConstants.Paths.vmHome,
            backupsPath: RuntimeControlClientConstants.Paths.backups,
            redisBackupsPath: RuntimeControlClientConstants.Paths.redisBackups
        )
    }

}

