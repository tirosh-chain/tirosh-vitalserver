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
    private let operationStateReader: any RuntimeOperationStateReading
    private let observabilityReader: any RuntimeObservabilityReading
    private let fileReader: any RuntimeHostFileReading
    private let settingsReader: any RuntimeSettingsReading

    public init(releaseInfo: RuntimeReleaseInfo) {
        self.init(
            releaseInfo: releaseInfo,
            operationLeaseReader: UnavailableRuntimeOperationLeaseReader(
                reason: "runtime operation lease owner unavailable for default read worker"
            )
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        guestAddressProvider: any RuntimeGuestAddressProvider = UnavailableRuntimeGuestAddressProvider(
            reason: "runtime Guest address owner unavailable for default read worker"
        ),
        vmLifecycleResourceReader: any RuntimeVMLifecycleResourceReading = UnavailableRuntimeVMLifecycleResourceReader(
            reason: "runtime VM lifecycle owner unavailable for default read worker"
        )
    ) {
        let fileReader = SystemRuntimeHostFileReader()
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(
                guestAddressProvider: guestAddressProvider,
                vmLifecycleResourceReader: vmLifecycleResourceReader
            ),
            operationStateReader: SystemRuntimeOperationStateReader.live(
                operationLeaseReader: operationLeaseReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(paths: RuntimeObservabilityPaths()),
            fileReader: fileReader,
            settingsReader: SystemRuntimeSettingsReader()
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: any RuntimeStatusReading,
        operationStateReader: any RuntimeOperationStateReading = SystemRuntimeOperationStateReader.live(),
        observabilityReader: any RuntimeObservabilityReading = SystemRuntimeObservabilityReader.live(paths: RuntimeObservabilityPaths()),
        fileReader: any RuntimeHostFileReading,
        settingsReader: any RuntimeSettingsReading
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.operationStateReader = operationStateReader
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

    public func loadOperationState() async -> RuntimeOperationState {
        operationStateReader.loadOperationState()
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

    public func loadVitalDBBeds() -> RuntimeVitalBedHistory {
        observabilityReader.loadVitalDBBeds()
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

    public func loadRuntimeDataBackups() throws -> [RuntimeBackup] {
        try fileReader.runtimeDataBackups()
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
        let installed = InstalledRuntimePaths.defaultInstalled
        return RuntimeInstallInfo(
            appBundlePath: Bundle.main.bundlePath,
            packageIdentifier: RuntimeControlClientConstants.Product.packageIdentifier,
            runtimeHomePath: installed.runtimeHome.path,
            backupsPath: installed.backupsDirectory.path,
            redisBackupsPath: installed.redisBackupsDirectory.path,
            runtimeDataBackupsPath: installed.vitalServerHelperBackupsDirectory.path
        )
    }
}

protocol RuntimeOperationStateReading: Sendable {
    func loadOperationState() -> RuntimeOperationState
}

struct SystemRuntimeOperationStateReader: RuntimeOperationStateReading, @unchecked Sendable {
    private let resourceReader: any RuntimeOperationStateResourceReading
    private let now: @Sendable () -> Date

    init(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        installStateReader: @escaping @Sendable () -> RuntimeInstallStateRead = {
            RuntimeInstallStateRead.unavailable()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            resourceReader: HostRuntimeOperationStateResourceReader(
                operationLeaseReader: operationLeaseReader,
                installStateReader: installStateReader
            ),
            now: now
        )
    }

    init(
        resourceReader: any RuntimeOperationStateResourceReading,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.resourceReader = resourceReader
        self.now = now
    }

    static func live() -> Self {
        Self.live(
            operationLeaseReader: UnavailableRuntimeOperationLeaseReader(
                reason: "runtime operation lease owner unavailable for default operation-state reader"
            )
        )
    }

    static func live(
        operationLeaseReader: any RuntimeOperationLeaseReading
    ) -> Self {
        return Self(
            resourceReader: HostRuntimeOperationStateResourceReader.live(operationLeaseReader: operationLeaseReader)
        )
    }

    func loadOperationState() -> RuntimeOperationState {
        let snapshot = resourceReader.loadResourceSnapshot()
        return RuntimeOperationState(
            activeOperation: nil,
            install: RuntimeInstallOperationState.fromInstallStateRead(snapshot.install),
            lease: leaseState(from: snapshot.lease, now: now())
        )
    }

    private func leaseState(
        from loadResult: RuntimeOperationLeaseLoadResult,
        now: Date
    ) -> RuntimeOperationLeaseState {
        switch loadResult {
        case .missing:
            return .unavailable()
        case .failed(let message):
            return .failed(readError: message)
        case .loaded(let document):
            return leaseState(from: document, now: now)
        }
    }

    private func leaseState(
        from document: RuntimeOperationLeaseDocument,
        now: Date
    ) -> RuntimeOperationLeaseState {
        guard let expiresAt = document.expiresAt else {
            return .loaded(document)
        }
        guard let expirationDate = ISO8601DateFormatter().date(from: expiresAt) else {
            return .failed(readError: "runtime operation lease expiresAt is invalid operationId=\(document.operationId) expiresAt=\(expiresAt)")
        }
        guard now > expirationDate else {
            return .loaded(document)
        }
        let expiredSeconds = Int(now.timeIntervalSince(expirationDate).rounded())
        return .stale(
            document,
            staleReason: "runtime operation lease expired operationId=\(document.operationId) expiresAt=\(expiresAt) expiredSeconds=\(expiredSeconds)"
        )
    }
}
