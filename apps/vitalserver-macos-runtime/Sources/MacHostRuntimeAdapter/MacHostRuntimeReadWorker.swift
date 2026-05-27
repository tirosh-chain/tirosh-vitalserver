import Foundation
import Contracts
import Core
import RuntimeControl

/// Owns read-only host snapshots that may touch disk, SQLite, logs, or subprocess-backed health checks.
/// SwiftUI and the development API call through this actor so MainActor only publishes results.
public actor MacHostRuntimeReadWorker {
    private let releaseInfo: RuntimeReleaseInfo
    private let statusReader: any RuntimeStatusReading
    private let fileReader: any RuntimeHostFileReading
    private let settingsReader: any RuntimeSettingsReading

    public init(releaseInfo: RuntimeReleaseInfo) {
        let fileReader = SystemRuntimeHostFileReader()
        let statusReader = SystemRuntimeStatusReader(paths: RuntimePaths())
        self.init(
            releaseInfo: releaseInfo,
            statusReader: statusReader,
            fileReader: fileReader,
            settingsReader: SystemRuntimeSettingsReader(statusReader: statusReader)
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: any RuntimeStatusReading,
        fileReader: any RuntimeHostFileReading,
        settingsReader: any RuntimeSettingsReading
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
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

    public func loadBackups(latestBackupPath: String?) -> [RuntimeBackup] {
        fileReader.backups(latestBackupPath: latestBackupPath)
    }

    public func loadRedisBackups() -> [RuntimeBackup] {
        fileReader.redisBackups()
    }

    public func updateBundleSummary(url: URL) -> String {
        fileReader.updateBundleSummary(url: url)
    }

    public func vitalFileFolders(root: String) -> [VitalFilesFolder] {
        fileReader.vitalFileFolders(root: root)
    }

    public func legacyCommandProgressLine() -> String? {
        statusReader.legacyCommandProgressLine()
    }

    public func loadReleaseInfo() -> RuntimeReleaseInfo {
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
