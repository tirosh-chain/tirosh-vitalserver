import Foundation
import RuntimeControl
import Contracts
import Errors

@MainActor
public final class RuntimeViewModel: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var settings = RuntimeSettings()
    @Published var selectedBundleURL: URL?
    @Published var selectedBundleSummary = ""
    @Published var selectedBundleVerification = ""
    @Published var selectedBundleVerified = false
    @Published var backups: [RuntimeBackup] = []
    @Published var selectedBackupPath: String?
    @Published var backupListErrorMessage: String?
    private let helperMessageLog: any RuntimeHelperMessageLogging
    @Published var message = AppConstants.StatusText.ready {
        didSet {
            guard message != oldValue else {
                return
            }
            helperMessageLog.append(message)
        }
    }
    @Published var operationDetail = ""
    @Published var logText = AppConstants.StatusText.ready
    @Published var logLineLimit = 500
    @Published var selectedLogSource = RuntimeLogSource.helperMessage
    @Published var logStreaming = true
    @Published var isBusy = false
    @Published var isApplyingUpdateBundle = false
    @Published var isCreatingRedisBackup = false
    var isRefreshingLogs = false
    @Published var releaseInfo = RuntimeReleaseInfo.generated
    @Published var installationInfo = RuntimeInstallInfo()
    @Published var runtimeEvents = RuntimeEventHistory(events: [])
    @Published var runtimeEventsLast24HoursCount = 0
    @Published var runtimeEventLimit = 50
    @Published var runtimeEventPeriod = RuntimeEventPeriodOption.last24Hours.rawValue
    @Published var runtimeEventFilter = ""
    @Published var vitalDBObservationSnapshot = RuntimeVitalDBObservationSnapshot.unavailable()
    @Published var vitalRecorders = RuntimeVitalRecorderHistory()
    @Published var vitalRelationships = RuntimeVitalRelationshipHistory()
    @Published var containerObservation: RuntimeContainerObservation?
    @Published var remoteConsoleHTTP: String?
    @Published var remoteConsoleStartedAt: String?
    @Published var testKitStatus = RuntimeTestKitStatus(enabled: false, state: .disabled)
    @Published var selectedTestKitSessionID = ""
    @Published var selectedTestKitBedRoomNames: Set<String> = []
    @Published var testKitVrcode = RuntimeViewModel.generatedTestKitVrcode()
    @Published var testKitOrphanVrcode = ""
    @Published var testKitScenario = RuntimeTestKitScenario.normal
    @Published var testKitSignalProfile = RuntimeTestKitSignalProfile.normal
    @Published var testKitRecorderCount = 1
    @Published var testKitBedCount = 1
    @Published var testKitBedPrefix = "testkit-bed"
    @Published var testKitIntervalSeconds = 1.0
    @Published var testKitDurationSeconds = 0.0
    @Published var testKitMaxMessages = 0
    @Published var testKitShiftTime = true
    @Published var testKitGenerateFrames = true
    @Published var isRunningTestKitAction = false
    @Published var testKitActionMessage = ""

    let controlClient: any RuntimeControlClient
    let hostClient: any RuntimeHostClient
    let testKitController: (any RuntimeTestKitControlling)?
    private let localAPISettings: (any RuntimeControlLocalAPISettingsApplying)?
    private let snapshots: RuntimeViewModelSnapshotLoader
    private let statusRefresher: RuntimeViewModelStatusRefresher
    private let observabilityRefresher: RuntimeViewModelObservabilityRefresher
    private let commandActionRunner = RuntimeViewModelCommandActionRunner()
    private let healthNotifications: any HealthNotifying
    private let healthNotificationCoordinator: RuntimeHealthNotificationCoordinator
    let nativeShell: any RuntimeNativeShell
    let backupSelectionPolicy = RuntimeBackupSelectionPolicy()
    let presentationFormatter = RuntimePresentationFormatter()
    let updateBundleVerifier = RuntimeViewModelUpdateBundleVerifier()
    let testKitStatePolicy = RuntimeViewModelTestKitStatePolicy()
    let navigationCoordinator = RuntimeViewModelNavigationCoordinator()
    private let settingsValidator = RuntimeSettingsValidator()
    private let vitalFilesDirectoryPolicy = RuntimeVitalFilesDirectoryPolicy()
    private var lastDefaultVitalServerURL = ""
    private var lastDefaultRemoteConsoleURL = ""

    public init(
        controlClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        testKitController: (any RuntimeTestKitControlling)? = nil,
        snapshotReader: (any RuntimeViewModelSnapshotReading)? = nil,
        initialSettings: RuntimeSettings? = nil,
        localAPISettings: (any RuntimeControlLocalAPISettingsApplying)? = nil,
        healthNotifications: any HealthNotifying = NoopHealthNotifier(),
        nativeShell: any RuntimeNativeShell = NoopRuntimeNativeShell(),
        helperMessageLog: any RuntimeHelperMessageLogging = NoopRuntimeHelperMessageLog()
    ) {
        self.controlClient = controlClient
        self.hostClient = hostClient
        self.testKitController = testKitController
        self.localAPISettings = localAPISettings
        self.helperMessageLog = helperMessageLog
        let snapshots = RuntimeViewModelSnapshotLoader(
            controlClient: controlClient,
            hostClient: hostClient,
            snapshotReader: snapshotReader,
            localAPISettings: localAPISettings
        )
        self.snapshots = snapshots
        self.statusRefresher = RuntimeViewModelStatusRefresher(snapshots: snapshots)
        self.observabilityRefresher = RuntimeViewModelObservabilityRefresher(snapshots: snapshots)
        self.healthNotifications = healthNotifications
        self.healthNotificationCoordinator = RuntimeHealthNotificationCoordinator(notifier: self.healthNotifications)
        self.nativeShell = nativeShell
        let initialSettings = localAPISettings?.settingsWithLocalAPIPort(
            initialSettings ?? self.controlClient.loadSettings()
        ) ?? (initialSettings ?? self.controlClient.loadSettings())
        self.settings = initialSettings
        syncAdvertisedServiceURLDefaults()
        self.installationInfo = self.controlClient.loadInstallInfo()
        self.healthNotifications.configure()
        self.helperMessageLog.append(message)
    }

    var capabilities: RuntimeControlCapabilities {
        controlClient.capabilities
    }

    var selectedBundleConfirmation: String {
        presentationFormatter.selectedBundleConfirmation(bundlePath: selectedBundlePath)
    }

    var selectedBundlePath: String? {
        selectedBundleURL?.path
    }

    var hasSelectedBundle: Bool {
        selectedBundleURL != nil
    }

    var hasSelectedBackup: Bool {
        selectedBackupPath != nil
    }

    var applySettingsConfirmation: String {
        presentationFormatter.applySettingsConfirmation(settings: settings)
    }

    var shouldShowUpdateProgress: Bool {
        isApplyingUpdateBundle || presentationFormatter.updateOperationInProgress(status)
    }

    var updateProgressMessage: String {
        if isApplyingUpdateBundle {
            return operationDetail.isEmpty ? message : operationDetail
        }
        return presentationFormatter.updateOperationDisplayMessage(status) ?? message
    }

    func refresh() async {
        await loadRuntimeSettings()
        applyStatusRefreshResult(await statusRefresher.refreshStatus(settings: settings, isBusy: isBusy))
        await refreshReleaseInfo()
        await refreshBackupList()
        await refreshRuntimeEvents()
        await refreshVitalRecorders()
        healthNotificationCoordinator.handleTransition(to: status)
    }

    public func updateRemoteConsoleStatus(http: String?, startedAt: String?) {
        remoteConsoleHTTP = http
        remoteConsoleStartedAt = startedAt
    }

    func refreshHealthStatus() async {
        applyStatusRefreshResult(await statusRefresher.refreshHealthStatus(settings: settings, isBusy: isBusy))
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        applyStatusRefreshResult(await statusRefresher.healthCheckStatus(
            settings: settings,
            completedMessage: AppConstants.StatusText.healthCheckCompleted
        ))
        await refreshRuntimeEvents()
        await refreshVitalRecorders()
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func refreshRuntimeEvents() async {
        let refreshed = await observabilityRefresher.refreshRuntimeEvents(
            limit: runtimeEventLimit,
            periodRawValue: runtimeEventPeriod,
            filterRawValue: runtimeEventFilter,
            statusContainerObservation: status.containerObservation
        )
        runtimeEvents = refreshed.events
        runtimeEventsLast24HoursCount = refreshed.last24HoursCount
        containerObservation = refreshed.containerObservation
    }

    func refreshVitalRecorders() async {
        let refreshed = await observabilityRefresher.refreshVitalObservability()
        vitalDBObservationSnapshot = refreshed.observationSnapshot
        vitalRecorders = refreshed.recorders
        vitalRelationships = refreshed.relationships
    }

    func uninstallRuntime(clean: Bool = false) async {
        guard controlClient.capabilities.canUninstallRuntime else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let didUninstall = await runClientAction(
            preparingMessage: AppConstants.StatusText.uninstallPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.uninstallRunning,
            successMessage: clean
                ? AppConstants.StatusText.cleanUninstallCompleted
                : AppConstants.StatusText.uninstallCompleted,
            action: { try await self.controlClient.uninstallRuntime(clean: clean) }
        )
        if didUninstall {
            await quitAfterSuccessfulUninstall()
        } else {
            await refreshHealthStatus()
        }
    }

    func prepareApplySettings() -> Bool {
        normalizeAdvertisedURLSettings()
        return validateSettings()
    }

    func applySettings() async {
        guard canApplySettingsForCurrentConnection else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        normalizeAdvertisedURLSettings()
        guard validateSettings() else {
            return
        }
        let settingsToApply = settings
        let didSave = await runClientAction(
            preparingMessage: AppConstants.StatusText.settingsApplyPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.settingsApplyRunning,
            successMessage: AppConstants.StatusText.settingsApplied,
            action: { try await self.controlClient.applySettings(settingsToApply) }
        )
        if didSave {
            localAPISettings?.apply(settings: settingsToApply)
            settings.adminPassword = ""
            settings.changeAdminPassword = false
            await waitForAppliedSettings()
        }
        await refreshHealthStatus()
    }

    func chooseVitalFilesDirectory() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        if let url = nativeShell.chooseDirectory(prompt: AppConstants.Actions.chooseDirectory) {
            if let validationMessage = vitalFilesDirectoryPolicy.validationMessage(for: url) {
                message = validationMessage
                return
            }
            do {
                try nativeShell.createDirectory(url)
            } catch {
                message = AppConstants.StatusText.folderCreateFailed(error.localizedDescription)
                return
            }
            settings.vitalFilesDirectory = url.path
        }
    }

    func syncAdvertisedURLWithProxyIfNeeded() {
        normalizeAdvertisedURLSettings()
        syncAdvertisedServiceURLDefaults()
    }

    func repairProxyPort() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let proxyPort = status.proxyPort
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.proxyRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.proxyRepairRunning,
            successMessage: AppConstants.StatusText.proxyRepairCompleted,
            action: { try await self.controlClient.repairProxy(proxyPort: proxyPort) }
        )
        await refreshHealthStatus()
    }

    func repairDatastore() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.datastoreRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.datastoreRepairRunning,
            successMessage: AppConstants.StatusText.datastoreRepairCompleted,
            action: { try await self.controlClient.repairDatastore() }
        )
        await refreshHealthStatus()
    }

    func repairVMDisk() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.vmDiskRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.vmDiskRepairRunning,
            successMessage: AppConstants.StatusText.vmDiskRepairCompleted,
            action: { try await self.controlClient.repairVMDisk() }
        )
        await refreshHealthStatus()
    }

    func repairRuntimeServices() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeServicesRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeServicesRepairRunning,
            successMessage: AppConstants.StatusText.runtimeServicesRepaired,
            action: { try await self.controlClient.repairRuntimeServices() }
        )
        await refreshHealthStatus()
    }

    func startRuntimeServices() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeServicesStartPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeServicesStartRunning,
            successMessage: AppConstants.StatusText.runtimeServicesStarted,
            action: { try await self.controlClient.startRuntimeServices() }
        )
        await refreshHealthStatus()
    }

    func stopRuntimeServices() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeServicesStopPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeServicesStopRunning,
            successMessage: AppConstants.StatusText.runtimeServicesStopped,
            action: { try await self.controlClient.stopRuntimeServices() }
        )
        await refresh()
    }

    public func relaunchHelper() {
        nativeShell.relaunchHelper()
    }

    public func terminateHelper() {
        nativeShell.terminate()
    }

    private func validateSettings() -> Bool {
        let result = settingsValidator.validate(settings, installedSettings: controlClient.loadSettings())
        if case .invalid(let validationMessage) = result {
            message = validationMessage
        }
        return result.isValid
    }

    private func loadRuntimeSettings() async {
        let nextSettings = await snapshots.loadSettings()
        settings = nextSettings
        syncAdvertisedServiceURLDefaults()
    }

    private func normalizeAdvertisedURLSettings() {
        settings.publicHost = ""
        settings.publicPort = settings.proxyPort
    }

    private func syncAdvertisedServiceURLDefaults() {
        let nextDefaultVitalServerURL = AppConstants.Product.vitalServerURL(proxyPort: settings.proxyPort)
        let nextDefaultRemoteConsoleURL = AppConstants.Product.remoteConsoleURL(port: settings.runtimeControlPort)

        if settings.vitalServerURL.isEmpty || settings.vitalServerURL == lastDefaultVitalServerURL {
            settings.vitalServerURL = nextDefaultVitalServerURL
        }
        if settings.remoteConsoleURL.isEmpty || settings.remoteConsoleURL == lastDefaultRemoteConsoleURL {
            settings.remoteConsoleURL = nextDefaultRemoteConsoleURL
        }

        lastDefaultVitalServerURL = nextDefaultVitalServerURL
        lastDefaultRemoteConsoleURL = nextDefaultRemoteConsoleURL
    }

    func refreshBackupList() async {
        do {
            backups = try await snapshots.loadBackups(latestBackupPath: status.latestBackup)
            backupListErrorMessage = nil
        } catch {
            backups = []
            selectedBackupPath = nil
            backupListErrorMessage = AppConstants.StatusText.backupListLoadFailed(error.localizedDescription)
            return
        }
        selectedBackupPath = backupSelectionPolicy.selectedBackupPath(
            from: backups,
            currentSelection: selectedBackupPath
        )
    }

    private func refreshReleaseInfo() async {
        if let loaded = await snapshots.loadReleaseInfoIfAvailable() {
            releaseInfo = loaded
        }
    }

    private var canApplySettingsForCurrentConnection: Bool {
        controlClient.capabilities.canEditVMResources
            || controlClient.capabilities.canEditNetworkExposure
            || controlClient.capabilities.canOpenLocalFiles
            || controlClient.capabilities.canResetAdminPassword
    }

    func runClientAction(
        preparingMessage: String,
        waitingMessage: String,
        runningMessage: String,
        successMessage: String,
        refreshCommandLog: Bool = true,
        action: @escaping () async throws -> RuntimeCommandResult
    ) async -> Bool {
        await commandActionRunner.run(
            request: RuntimeClientActionRequest(
                preparingMessage: preparingMessage,
                waitingMessage: waitingMessage,
                runningMessage: runningMessage,
                successMessage: successMessage,
                refreshCommandLog: refreshCommandLog
            ),
            presenter: self,
            action: action
        )
    }

    func refreshOperationDetail(pendingDetail: String) async {
        applyStatusRefreshResult(await statusRefresher.operationDetail(
            settings: settings,
            pendingDetail: pendingDetail
        ))
    }

    private func quitAfterSuccessfulUninstall() async {
        message = [
            message,
            AppConstants.StatusText.applicationWillQuit,
        ].joined(separator: "\n\n")
        try? await Task.sleep(nanoseconds: 800_000_000)
        nativeShell.terminate()
    }

    private func waitForAppliedSettings() async {
        for _ in 0..<12 {
            await loadRuntimeSettings()
            applyStatusRefreshResult(await statusRefresher.refreshHealthStatus(settings: settings, isBusy: isBusy))
            await refreshLogsIfLive()
            if RuntimeReadinessPolicy.isReady(status) || !settings.restartAfterSave {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

}

private extension RuntimeViewModel {
    func applyStatusRefreshResult(_ result: RuntimeViewModelStatusRefreshResult) {
        status = result.status
        containerObservation = result.status.containerObservation
        if let selectedLogSource = result.selectedLogSource {
            self.selectedLogSource = selectedLogSource
        }
        if let message = result.message {
            self.message = message
        }
        if let operationDetail = result.operationDetail {
            self.operationDetail = operationDetail
        }
    }
}

extension RuntimeViewModel: RuntimeClientActionPresentation {}

