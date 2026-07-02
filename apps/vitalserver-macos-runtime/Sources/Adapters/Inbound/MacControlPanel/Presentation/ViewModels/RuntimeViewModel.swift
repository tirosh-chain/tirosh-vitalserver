import Foundation
import RuntimeControl
import Contracts
import Errors

@MainActor
public final class RuntimeViewModel: ObservableObject {
    @Published var status: RuntimeStatus
    @Published private(set) var runtimeSettings = RuntimeSettings()
    @Published private(set) var savedSettings = RuntimeSettings()
    @Published var settings = RuntimeSettings()
    @Published var selectedBundleURL: URL?
    @Published var selectedBundleSummary = ""
    @Published var selectedBundleVerification = ""
    @Published var selectedBundleVerified = false
    @Published var backups: [RuntimeBackup] = []
    @Published var selectedBackupPath: String?
    @Published var backupListErrorMessage: String?
    @Published var redisBackups: [RuntimeBackup] = []
    @Published var selectedRedisBackupPath: String?
    @Published var redisBackupListErrorMessage: String?
    @Published var runtimeDataBackups: [RuntimeBackup] = []
    @Published var selectedRuntimeDataBackupPath: String?
    @Published var runtimeDataBackupListErrorMessage: String?
    private let helperMessageLog: any RuntimeHelperMessageLogging
    @Published var message = AppConstants.StatusText.ready {
        didSet {
            guard message != oldValue else {
                return
            }
            helperMessageLog.append(message)
        }
    }
    @Published var settingsValidationMessage: String?
    @Published var operationDetail = ""
    @Published var logText = AppConstants.StatusText.ready
    @Published var logLineLimit = 500
    @Published var selectedLogSource = RuntimeLogSource.helperMessage
    @Published var logStreaming = true
    @Published var isBusy = false
    @Published var isApplyingUpdateBundle = false
    @Published var isCreatingRedisBackup = false
    @Published var isImportingRedisBackup = false
    @Published var isRestoringRedisBackup = false
    @Published var isCreatingRuntimeDataBackup = false
    @Published var isImportingRuntimeDataBackup = false
    @Published var isRestoringRuntimeDataBackup = false
    @Published var isRollingBackRuntime = false
    var isRefreshingLogs = false
    @Published var releaseInfo = RuntimeReleaseInfo.generated
    @Published var releaseInfoErrorMessage: String?
    @Published var installationInfo = RuntimeInstallInfo()
    @Published var runtimeEvents = RuntimeEventHistory(events: [])
    @Published var runtimeEventsLast24HoursCount = 0
    @Published var runtimeEventLimit = 50
    @Published var runtimeEventPeriod = RuntimeEventPeriodOption.last24Hours.rawValue
    @Published var runtimeEventFilter = ""
    @Published var vitalDBObservationSnapshot = RuntimeVitalDBObservationSnapshot.unavailable()
    @Published var vitalRecorders = RuntimeVitalRecorderHistory()
    @Published var recorderActivityWindows: [String: RuntimeVitalRecorderActivityWindow] = [:]
    @Published var vitalRelationships = RuntimeVitalRelationshipHistory()
    @Published var isRunningVitalDBVisibilityAction = false
    @Published var vitalDBVisibilityActionMessage = ""
    @Published var remoteConsoleHTTP: String?
    @Published var remoteConsoleStartedAt: String?
    @Published var labScenarios = RuntimeLabScenarioList.unavailable(readError: "Product Lab scenarios have not been loaded.")
    @Published var labVitalFiles = RuntimeLabVitalFileList.unavailable(readError: "Product Lab .vital files have not been loaded.")
    @Published var labBeds = RuntimeLabBedList.unavailable(readError: "Product Lab beds have not been loaded.")
    @Published var labRecorders = RuntimeLabRecorderList.unavailable(readError: "Product Lab recorders have not been loaded.")
    @Published var selectedLabScenarioID = ""
    @Published var selectedLabVitalFileGuestPath = ""
    @Published var labVitalFileQuery = ""
    @Published var selectedLabBedID = ""
    @Published var selectedLabRecorderID = ""
    @Published var labSessionName = ""
    @Published var labRecorderCount = 1
    @Published var labBedCount = 1
    @Published var labBedPrefix = "Lab bed"
    @Published var labTargetURL = "http://edge/"
    @Published var selectedLabSessionID = ""
    @Published var labSessionResponse = RuntimeLabSessionResponse.unavailable(readError: "No Product Lab session has been selected.")
    @Published var labVitalFilePath = ""
    @Published var labVitalFileUploadResponse = RuntimeLabVitalFileUploadResponse.unavailable(readError: "No .vital file has been uploaded.")
    @Published var isRunningLabAction = false
    @Published var labActionMessage = ""
    @Published var labActionMessageTone = RuntimeLabActionMessageTone.neutral

    let controlClient: any RuntimeControlClient
    let hostClient: any RuntimeHostClient
    private let localAPISettings: (any RuntimeControlLocalAPISettingsApplying)?
    private let snapshots: RuntimePresentationSnapshotLoader
    private let statusRefresher: RuntimeStatusRefresher
    private let observabilityRefresher: RuntimeObservabilityRefresher
    private let commandActionRunner = RuntimeClientActionRunner()
    private let healthNotifications: any HealthNotifying
    private let healthNotificationCoordinator: RuntimeHealthNotificationCoordinator
    let nativeShell: any RuntimeNativeShell
    let backupSelectionPolicy = RuntimeBackupSelectionPolicy()
    let presentationFormatter = RuntimePresentationFormatter()
    let updateBundleVerifier = RuntimeUpdateBundleVerifier()
    let navigationCoordinator = RuntimeNavigationCoordinator()
    private let settingsValidator = RuntimeSettingsValidator()
    private let vitalFilesDirectoryPolicy = RuntimeVitalFilesDirectoryPolicy()

    public init(
        controlClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        snapshotReader: (any RuntimeViewModelSnapshotReading)? = nil,
        initialSettings: RuntimeSettings? = nil,
        initialStatus: RuntimeStatus? = nil,
        localAPISettings: (any RuntimeControlLocalAPISettingsApplying)? = nil,
        healthNotifications: any HealthNotifying = NoopHealthNotifier(),
        nativeShell: any RuntimeNativeShell = NoopRuntimeNativeShell(),
        helperMessageLog: any RuntimeHelperMessageLogging = NoopRuntimeHelperMessageLog()
    ) {
        self.controlClient = controlClient
        self.hostClient = hostClient
        self.localAPISettings = localAPISettings
        self.helperMessageLog = helperMessageLog
        let loadedSettings = initialSettings ?? controlClient.loadSettings()
        let resolvedSettings = localAPISettings?.settingsWithLocalAPIPort(loadedSettings) ?? loadedSettings
        let displaySettings = Self.settingsWithAdvertisedServiceURLPresets(
            resolvedSettings,
            fillMissing: initialSettings == nil
        )
        let displayRuntimeSettings = Self.settingsWithAdvertisedServiceURLPresets(
            displaySettings.runtimeAppliedSettings,
            fillMissing: initialSettings == nil
        )
        let resolvedStatus = initialStatus ?? controlClient.loadStatus(settings: displayRuntimeSettings)
        self.runtimeSettings = displayRuntimeSettings
        self.savedSettings = displaySettings
        self.settings = displaySettings
        self.status = resolvedStatus
        let snapshots = RuntimePresentationSnapshotLoader(
            controlClient: controlClient,
            hostClient: hostClient,
            snapshotReader: snapshotReader,
            localAPISettings: localAPISettings
        )
        self.snapshots = snapshots
        self.statusRefresher = RuntimeStatusRefresher(snapshots: snapshots)
        self.observabilityRefresher = RuntimeObservabilityRefresher(snapshots: snapshots)
        self.healthNotifications = healthNotifications
        self.healthNotificationCoordinator = RuntimeHealthNotificationCoordinator(notifier: self.healthNotifications)
        self.nativeShell = nativeShell
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

    var hasSelectedRedisBackup: Bool {
        selectedRedisBackupPath != nil
    }

    var hasSelectedRuntimeDataBackup: Bool {
        selectedRuntimeDataBackupPath != nil
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

    var backupOperationProgressMessage: String {
        operationDetail.isEmpty ? message : operationDetail
    }

    var isRuntimeDataBackupOperationInProgress: Bool {
        isCreatingRuntimeDataBackup
            || isImportingRuntimeDataBackup
            || isRestoringRuntimeDataBackup
    }

    var isRedisBackupOperationInProgress: Bool {
        isCreatingRedisBackup
            || isImportingRedisBackup
            || isRestoringRedisBackup
    }

    func refresh() async {
        await loadRuntimeSettings()
        applyStatusRefreshResult(await statusRefresher.refreshStatus(settings: runtimeSettings, isBusy: isBusy))
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

    public func updateRemoteConsoleStatus(_ read: RuntimeControlLocalAPIStatusRead) {
        updateRemoteConsoleStatus(http: read.http, startedAt: read.startedAt)
    }

    func refreshHealthStatus() async {
        applyStatusRefreshResult(await statusRefresher.refreshHealthStatus(settings: runtimeSettings, isBusy: isBusy))
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        applyStatusRefreshResult(await statusRefresher.healthCheckStatus(
            settings: runtimeSettings,
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
            filterRawValue: runtimeEventFilter
        )
        runtimeEvents = refreshed.events
        runtimeEventsLast24HoursCount = refreshed.last24HoursCount
    }

    func refreshVitalRecorders() async {
        let refreshed = await observabilityRefresher.refreshVitalObservability()
        vitalDBObservationSnapshot = refreshed.observationSnapshot
        vitalRecorders = refreshed.recorders
        vitalRelationships = refreshed.relationships
    }

    func refreshVitalRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async {
        let window = await snapshots.loadVitalRecorderActivityWindow(query: query)
        recorderActivityWindows[recorderActivityWindowKey(query)] = window
    }

    func recorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow? {
        recorderActivityWindows[recorderActivityWindowKey(query)]
    }

    func hideVitalDBRecorder(vrcode: String) async {
        await runVitalDBVisibilityAction(successMessage: "VRecorder hidden.") {
            try await controlClient.hideVitalDBRecorders(.init(vrcodes: [vrcode]))
        }
    }

    func unhideVitalDBRecorder(vrcode: String) async {
        await runVitalDBVisibilityAction(successMessage: "VRecorder visible.") {
            try await controlClient.unhideVitalDBRecorders(.init(vrcodes: [vrcode]))
        }
    }

    func deleteVitalDBRecorder(vrcode: String) async {
        await runVitalDBVisibilityAction(successMessage: "Hidden VRecorder deleted.") {
            try await controlClient.deleteVitalDBRecorders(.init(vrcodes: [vrcode]))
        }
    }

    func hideVitalDBBed(bedID: String) async {
        await runVitalDBVisibilityAction(successMessage: "Bed hidden.") {
            try await controlClient.hideVitalDBBeds(.init(bedIDs: [bedID]))
        }
    }

    func unhideVitalDBBed(bedID: String) async {
        await runVitalDBVisibilityAction(successMessage: "Bed visible.") {
            try await controlClient.unhideVitalDBBeds(.init(bedIDs: [bedID]))
        }
    }

    func deleteVitalDBBed(bedID: String) async {
        await runVitalDBVisibilityAction(successMessage: "Hidden bed deleted.") {
            try await controlClient.deleteVitalDBBeds(.init(bedIDs: [bedID]))
        }
    }

    private func runVitalDBVisibilityAction(
        successMessage: String,
        action: () async throws -> RuntimeVitalRecorderHistory
    ) async {
        isRunningVitalDBVisibilityAction = true
        vitalDBVisibilityActionMessage = "Updating VitalDB visibility..."
        defer { isRunningVitalDBVisibilityAction = false }
        do {
            vitalRecorders = try await action()
            vitalDBVisibilityActionMessage = successMessage
        } catch {
            vitalDBVisibilityActionMessage = error.localizedDescription
        }
    }

    private func recorderActivityWindowKey(_ query: RuntimeVitalRecorderActivityWindowQuery) -> String {
        [
            query.vrcode,
            "\(query.bucketSeconds)",
            query.period.rawValue,
            query.pageIndex.map(String.init) ?? "latest",
        ].joined(separator: "|")
    }

    func uninstallRuntime(mode: RuntimeUninstallMode = .standard) async {
        guard controlClient.capabilities.canUninstallRuntime else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let uninstallResult = await runClientAction(
            preparingMessage: AppConstants.StatusText.uninstallPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.uninstallRunning,
            successMessage: mode.clean
                ? AppConstants.StatusText.cleanUninstallCompleted
                : AppConstants.StatusText.uninstallCompleted,
            action: { try await self.controlClient.uninstallRuntime(mode: mode) }
        )
        if uninstallResult.isSuccess {
            await quitAfterSuccessfulUninstall()
        } else {
            await refreshHealthStatus()
        }
    }

    func prepareApplySettings() -> Bool {
        normalizeAdvertisedURLSettings()
        normalizeRecorderArchiveSettings()
        return validateSettings()
    }

    func applySettings() async {
        guard canApplySettingsForCurrentConnection else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        normalizeAdvertisedURLSettings()
        normalizeRecorderArchiveSettings()
        guard validateSettings() else {
            return
        }
        var settingsToApply = settings
        settingsToApply.appliedVMSettings = nil
        let applySettingsResult = await runClientAction(
            preparingMessage: AppConstants.StatusText.settingsApplyPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.settingsApplyRunning,
            successMessage: AppConstants.StatusText.settingsApplied,
            action: { try await self.controlClient.applySettings(settingsToApply) }
        )
        if applySettingsResult.isSuccess {
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
        applyAdvertisedServiceURLPresets()
    }

    func repairProxyPort() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.proxyRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.proxyRepairRunning,
            successMessage: AppConstants.StatusText.proxyRepairCompleted,
            action: { try await self.hostClient.repairProxy() }
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
            action: { try await self.hostClient.repairDatastore() }
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
            action: { try await self.hostClient.repairVMDisk() }
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
            action: { try await self.hostClient.repairRuntimeServices() }
        )
        await refreshHealthStatus()
    }

    func restartVMRuntimeFromSettings() async {
        guard controlClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.restartVMRuntimePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.restartVMRuntimeRunning,
            successMessage: AppConstants.StatusText.restartVMRuntimeCompleted,
            action: { try await self.hostClient.repairRuntimeServices() }
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
            settingsValidationMessage = validationMessage
        } else {
            settingsValidationMessage = nil
        }
        return result.isValid
    }

    private func normalizeRecorderArchiveSettings() {
        settings.recorderIngress.rawArchiveEnabled = true
        settings.recorderIngress.rawArchiveAutoExportEnabled = true
    }

    private func loadRuntimeSettings() async {
        let nextSettings = await snapshots.loadSettings()
        let loadedSettings = Self.settingsWithAdvertisedServiceURLPresets(nextSettings, fillMissing: true)
        runtimeSettings = Self.settingsWithAdvertisedServiceURLPresets(loadedSettings.runtimeAppliedSettings, fillMissing: true)
        savedSettings = loadedSettings
        settings = loadedSettings
    }

    private func normalizeAdvertisedURLSettings() {
        settings.publicHost = ""
        settings.publicPort = settings.proxyPort
    }

    private func applyAdvertisedServiceURLPresets() {
        settings = Self.settingsWithAdvertisedServiceURLPresets(settings)
    }

    private static func settingsWithAdvertisedServiceURLPresets(
        _ input: RuntimeSettings,
        fillMissing: Bool = false
    ) -> RuntimeSettings {
        var settings = input
        if shouldUpdateInitialVitalServerURL(settings.vitalServerURL, fillMissing: fillMissing) {
            settings.vitalServerURL = RuntimeSettingsInitialValues.vitalServerURL(proxyPort: settings.proxyPort)
        }
        if shouldUpdateInitialRemoteConsoleURL(settings.remoteConsoleURL, fillMissing: fillMissing) {
            settings.remoteConsoleURL = RuntimeSettingsInitialValues.remoteConsoleURL(
                runtimeControlPort: settings.runtimeControlPort
            )
        }
        return settings
    }

    private static func shouldUpdateInitialVitalServerURL(_ value: String, fillMissing: Bool) -> Bool {
        if fillMissing && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return RuntimeSettingsInitialValues.isInitialVitalServerURL(value)
    }

    private static func shouldUpdateInitialRemoteConsoleURL(_ value: String, fillMissing: Bool) -> Bool {
        if fillMissing && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return RuntimeSettingsInitialValues.isInitialRemoteConsoleURL(value)
    }

    func refreshBackupList() async {
        do {
            backups = try await snapshots.loadBackups(latestBackupPath: status.latestBackup)
            backupListErrorMessage = nil
        } catch {
            backupListErrorMessage = AppConstants.StatusText.backupListLoadFailed(error.localizedDescription)
        }
        do {
            redisBackups = try await snapshots.loadRedisBackups()
            redisBackupListErrorMessage = nil
        } catch {
            redisBackupListErrorMessage = AppConstants.StatusText.backupListLoadFailed(error.localizedDescription)
        }
        do {
            runtimeDataBackups = try await snapshots.loadRuntimeDataBackups()
            runtimeDataBackupListErrorMessage = nil
        } catch {
            runtimeDataBackupListErrorMessage = AppConstants.StatusText.backupListLoadFailed(error.localizedDescription)
        }
        selectedBackupPath = backupSelectionPolicy.selectedBackupPath(
            from: backups,
            currentSelection: selectedBackupPath
        )
        selectedRuntimeDataBackupPath = backupSelectionPolicy.selectedBackupPath(
            from: runtimeDataBackups,
            currentSelection: selectedRuntimeDataBackupPath
        )
        selectedRedisBackupPath = backupSelectionPolicy.selectedBackupPath(
            from: redisBackups,
            currentSelection: selectedRedisBackupPath
        )
    }

    private func refreshReleaseInfo() async {
        switch await snapshots.loadReleaseInfoIfAvailable() {
        case .loaded(let loaded):
            releaseInfo = loaded
            releaseInfoErrorMessage = nil
        case .unavailable:
            releaseInfoErrorMessage = nil
        case .failed(let message):
            releaseInfoErrorMessage = AppConstants.StatusText.releaseMetadataLoadFailed(message)
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
    ) async -> RuntimeClientActionRunResult {
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
            settings: runtimeSettings,
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
            applyStatusRefreshResult(await statusRefresher.refreshHealthStatus(settings: runtimeSettings, isBusy: isBusy))
            await refreshLogsIfLive()
            if RuntimeReadinessPolicy.isReady(status) || !settings.restartAfterSave {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

}

private extension RuntimeViewModel {
    func applyStatusRefreshResult(_ result: RuntimeStatusRefreshResult) {
        status = result.status
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
