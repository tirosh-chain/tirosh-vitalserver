import Foundation
import Contracts
import Application
import RuntimeControl
import Errors

/// Owns read-only host snapshots that may touch disk, SQLite, logs, or subprocess-backed health checks.
/// SwiftUI and the development API call through this actor so MainActor only publishes results.
public actor MacRuntimeControlReadWorker {
    private let releaseInfo: RuntimeReleaseInfo
    private let statusReader: any RuntimeStatusReading
    private let observabilityReader: any RuntimeObservabilityReading
    private let fileReader: any RuntimeHostFileReading
    private let settingsReader: any RuntimeSettingsReading

    public init(releaseInfo: RuntimeReleaseInfo) {
        let paths = RuntimePaths()
        let fileReader = SystemRuntimeHostFileReader()
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: paths),
            observabilityReader: SystemRuntimeObservabilityReader.live(paths: paths),
            fileReader: fileReader,
            settingsReader: SystemRuntimeSettingsReader()
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: any RuntimeStatusReading,
        observabilityReader: any RuntimeObservabilityReading = SystemRuntimeObservabilityReader.live(paths: RuntimePaths()),
        fileReader: any RuntimeHostFileReading,
        settingsReader: any RuntimeSettingsReading
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.observabilityReader = observabilityReader
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
        observabilityReader.loadRuntimeEvents(limit: limit)
    }

    public func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        observabilityReader.loadRuntimeEvents(query: query)
    }

    public func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        observabilityReader.loadVitalDBObservationSnapshot()
    }

    public func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        observabilityReader.loadVitalDBRecorders()
    }

    public func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        observabilityReader.loadVitalDBRecorderSummaries()
    }

    public func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        observabilityReader.loadVitalDBRecorderActivityWindow(query: query)
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

    public func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult {
        fileReader.updateBundleSummaryResult(url: url)
    }

    public func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        try fileReader.vitalFileFolders(root: root)
    }

    public func loadReleaseInfo() -> RuntimeReleaseInfo {
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
