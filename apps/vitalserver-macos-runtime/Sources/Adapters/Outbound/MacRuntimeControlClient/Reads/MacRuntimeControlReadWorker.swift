import Foundation
import Contracts
import Application
import RuntimeControl
import Errors

/// Owns read-only host snapshots that may touch disk, SQLite, logs, or subprocess-backed health checks.
/// SwiftUI and the development API call through this actor so MainActor only publishes results.
public actor MacRuntimeControlReadWorker {
    private let releaseInfo: RuntimeReleaseInfo
    private let platformStateReader: any PlatformStateReading
    private let operationStateReader: any PlatformOperationStateReading
    private let observabilityReader: any RuntimeObservabilityReading
    private let fileReader: any RuntimeHostFileReading
    private let settingsReader: any RuntimeSettingsReading

    public init(
        releaseInfo: RuntimeReleaseInfo,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading = UnavailableRuntimeWorkflowOperationStateReader(
            reason: "workflow operation state owner unavailable for default read worker"
        ),
        guestAddressProvider: any RuntimeGuestAddressProvider = UnavailableRuntimeGuestAddressProvider(
            reason: "runtime Guest address owner unavailable for default read worker"
        ),
        vmLifecycleResourceReader: any RuntimeVMLifecycleResourceReading = UnavailableRuntimeVMLifecycleResourceReader(
            reason: "runtime VM lifecycle owner unavailable for default read worker"
        ),
        installedProductReleaseReader: (any InstalledProductReleaseReading)? = nil,
        hostSettingsReader: any RuntimeHostSettingsReading
    ) {
        let fileReader = SystemRuntimeHostFileReader()
        self.init(
            releaseInfo: releaseInfo,
            platformStateReader: SystemPlatformStateReader(
                guestAddressProvider: guestAddressProvider,
                vmLifecycleResourceReader: vmLifecycleResourceReader,
                installedProductReleaseReader: installedProductReleaseReader
            ),
            operationStateReader: SystemPlatformOperationStateReader.live(
                operationLeaseReader: operationLeaseReader,
                workflowOperationStateReader: workflowOperationStateReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(
                paths: RuntimeObservabilityPaths(),
                guestAddressProvider: guestAddressProvider
            ),
            fileReader: fileReader,
            settingsReader: SystemRuntimeSettingsReader(
                paths: RuntimeSettingsPaths(),
                fileStore: SystemRuntimeFileStore(),
                runCommand: ProcessRunner.runSync,
                hostSettingsReader: hostSettingsReader
            )
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading = UnavailableRuntimeWorkflowOperationStateReader(
            reason: "workflow operation state owner unavailable for default read worker"
        ),
        guestAddressProvider: any RuntimeGuestAddressProvider,
        vmLifecycleResourceReader: any RuntimeVMLifecycleResourceReading,
        installedProductReleaseReader: (any InstalledProductReleaseReading)? = nil,
        settingsReader: any RuntimeSettingsReading
    ) {
        let fileReader = SystemRuntimeHostFileReader()
        self.init(
            releaseInfo: releaseInfo,
            platformStateReader: SystemPlatformStateReader(
                guestAddressProvider: guestAddressProvider,
                vmLifecycleResourceReader: vmLifecycleResourceReader,
                installedProductReleaseReader: installedProductReleaseReader
            ),
            operationStateReader: SystemPlatformOperationStateReader.live(
                operationLeaseReader: operationLeaseReader,
                workflowOperationStateReader: workflowOperationStateReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(
                paths: RuntimeObservabilityPaths(),
                guestAddressProvider: guestAddressProvider
            ),
            fileReader: fileReader,
            settingsReader: settingsReader
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        platformStateReader: any PlatformStateReading,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading = UnavailableRuntimeWorkflowOperationStateReader(
            reason: "workflow operation state owner unavailable for default read worker"
        ),
        guestAddressProvider: any RuntimeGuestAddressProvider,
        settingsReader: any RuntimeSettingsReading
    ) {
        let fileReader = SystemRuntimeHostFileReader()
        self.init(
            releaseInfo: releaseInfo,
            platformStateReader: platformStateReader,
            operationStateReader: SystemPlatformOperationStateReader.live(
                operationLeaseReader: operationLeaseReader,
                workflowOperationStateReader: workflowOperationStateReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(
                paths: RuntimeObservabilityPaths(),
                guestAddressProvider: guestAddressProvider
            ),
            fileReader: fileReader,
            settingsReader: settingsReader
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        platformStateReader: any PlatformStateReading,
        operationStateReader: any PlatformOperationStateReading = SystemPlatformOperationStateReader.live(),
        observabilityReader: any RuntimeObservabilityReading = SystemRuntimeObservabilityReader.live(paths: RuntimeObservabilityPaths()),
        fileReader: any RuntimeHostFileReading,
        settingsReader: any RuntimeSettingsReading
    ) {
        self.releaseInfo = releaseInfo
        self.platformStateReader = platformStateReader
        self.operationStateReader = operationStateReader
        self.observabilityReader = observabilityReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
    }

    public func loadSettings() -> RuntimeSettings {
        settingsReader.load()
    }

    public func loadPlatformState(settings: RuntimeSettings) -> PlatformState {
        platformStateReader.loadPlatformState(settings: settings)
    }

    public func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        await platformStateReader.loadHealthStatus(settings: settings)
    }

    public func loadOperationState() async -> PlatformOperationState {
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

    public func loadVitalDBRecorderVitalFiles(
        vrcode: String
    ) -> RuntimeVitalRecorderVitalFileHistory {
        observabilityReader.loadVitalDBRecorderVitalFiles(vrcode: vrcode)
    }

    public func loadRecorderObservabilityDetail(
        vrcode: String
    ) -> RuntimeRecorderObservabilityDetail {
        observabilityReader.loadRecorderObservabilityDetail(vrcode: vrcode)
    }

    public func loadRecorderObservabilityTimeline(
        query: RuntimeRecorderObservabilityTimelineQuery
    ) -> RuntimeRecorderObservabilityTimeline {
        observabilityReader.loadRecorderObservabilityTimeline(query: query)
    }

    public func loadRecorderObservabilityIncidents(
        query: RuntimeRecorderObservabilityIncidentQuery
    ) -> RuntimeRecorderObservabilityIncidents {
        observabilityReader.loadRecorderObservabilityIncidents(query: query)
    }

    public func loadVitalDBRelationships() async -> RuntimeVitalRelationshipHistory {
        await observabilityReader.loadVitalDBRelationshipsAsync()
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

protocol PlatformOperationStateReading: Sendable {
    func loadOperationState() -> PlatformOperationState
}

struct SystemPlatformOperationStateReader: PlatformOperationStateReading, @unchecked Sendable {
    private let resourceReader: any PlatformOperationStateResourceReading
    private let now: @Sendable () -> Date

    init(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading = UnavailableRuntimeWorkflowOperationStateReader(
            reason: "workflow operation state owner unavailable for default operation-state reader"
        ),
        installStateReader: @escaping @Sendable () -> RuntimeInstallStateRead = {
            RuntimeInstallStateRead.unavailable()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            resourceReader: HostPlatformOperationStateResourceReader(
                operationLeaseReader: operationLeaseReader,
                workflowOperationStateReader: workflowOperationStateReader,
                installStateReader: installStateReader
            ),
            now: now
        )
    }

    init(
        resourceReader: any PlatformOperationStateResourceReading,
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
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading = UnavailableRuntimeWorkflowOperationStateReader(
            reason: "workflow operation state owner unavailable for default operation-state reader"
        )
    ) -> Self {
        return Self(
            resourceReader: HostPlatformOperationStateResourceReader.live(
                operationLeaseReader: operationLeaseReader,
                workflowOperationStateReader: workflowOperationStateReader
            )
        )
    }

    func loadOperationState() -> PlatformOperationState {
        let snapshot = resourceReader.loadResourceSnapshot()
        return PlatformOperationState(
            activeOperation: nil,
            install: RuntimeInstallOperationState.fromInstallStateRead(snapshot.install),
            lease: leaseState(from: snapshot.lease, now: now()),
            workflow: workflowState(from: snapshot.workflow)
        )
    }

    private func workflowState(
        from readResult: RuntimeWorkflowOperationStateReadResult
    ) -> RuntimeWorkflowOperationStateResource {
        switch readResult {
        case .missing:
            return .unavailable()
        case .failed(let reason):
            return .failed(readError: reason)
        case .loaded(let state):
            return .loaded(RuntimeWorkflowOperationStateDocument(
                operationID: state.operationID,
                operation: state.operation,
                phase: state.phase,
                currentStep: state.currentStep,
                stepStatus: state.stepStatus,
                message: state.message,
                reasonCodes: state.reasonCodes,
                startedAt: state.startedAt,
                updatedAt: state.updatedAt,
                completedAt: state.completedAt,
                revision: state.revision
            ))
        }
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
