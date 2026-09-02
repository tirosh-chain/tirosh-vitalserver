import Foundation
import RuntimeControl
import Contracts
import Errors

enum RuntimePlatformSettingsPresentationState: Equatable {
    case notRead
    case loaded
    case failed([RuntimeSettingsReadIssue])
}

@MainActor
public final class RuntimeViewModel: ObservableObject {
    @Published var status: PlatformState
    @Published var operationState: PlatformOperationState
    @Published private(set) var runtimeSettings = RuntimeSettings()
    @Published private(set) var savedSettings = RuntimeSettings()
    @Published var settings = RuntimeSettings()
    @Published private(set) var platformSettingsReadState: RuntimePlatformSettingsPresentationState = .notRead
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
    @Published var vitalBeds = RuntimeVitalBedHistory()
    @Published var recorderActivityWindows: [String: RuntimeVitalRecorderActivityWindow] = [:]
    @Published var recorderVitalFileHistories: [String: RuntimeVitalRecorderVitalFileHistory] = [:]
    @Published var recorderObservabilityDetails: [String: RuntimeRecorderObservabilityDetail] = [:]
    @Published var recorderObservabilityIncidents: [String: RuntimeRecorderObservabilityIncidents] = [:]
    @Published var vitalRelationships = RuntimeVitalRelationshipHistory() {
        didSet {
            vitalRelationshipPresentationIndex = RuntimeVitalRelationshipPresentationIndex(
                history: vitalRelationships
            )
        }
    }
    private var vitalRelationshipPresentationIndex = RuntimeVitalRelationshipPresentationIndex()
    @Published var redisRelayStatusRead = RuntimeRedisRelayStatusReadResult(
        readState: .notRead,
        document: nil,
        readError: nil
    )
    @Published private(set) var runtimeRedisRelaySettingsRead = RuntimeRedisRelaySettingsRead(
        state: .unavailable,
        settings: nil,
        readError: "Runtime Redis Relay settings have not been read."
    )
    @Published var runtimeStackStatus: RuntimeGuestControlStackStatus?
    @Published var runtimeStackReadError: String?
    @Published var runtimeServiceResources: [RuntimeGuestServiceResource] = []
    @Published var runtimeServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = []
    @Published var isRunningVitalDBVisibilityAction = false
    @Published var vitalDBVisibilityActionMessage = ""
    @Published var remoteConsoleHTTP: String?
    @Published var remoteConsoleStartedAt: String?
    @Published var labScenarios = RuntimeLabScenarioList.unavailable(readError: "Product Lab scenarios have not been loaded.")
    @Published var labVitalFiles = RuntimeLabVitalFileList.unavailable(readError: "Product Lab .vital files have not been loaded.")
    @Published var labBeds = RuntimeLabBedList.unavailable(readError: "Product Lab beds have not been loaded.")
    @Published var labRecorders = RuntimeLabRecorderList.unavailable(readError: "Product Lab recorders have not been loaded.")
    @Published var labSessions = RuntimeLabSessionList.unavailable(readError: "Product Lab sessions have not been loaded.")
    @Published var selectedLabScenarioID = ""
    @Published var selectedLabVitalFileRelativePath = ""
    @Published var labVitalFileQuery = ""
    @Published var selectedLabBedID = ""
    @Published var selectedLabRecorderID = ""
    @Published var labSessionName = ""
    @Published var labSessionBedIDs = ""
    @Published var labRecorderCount = 1
    @Published var labBedCount = 1
    @Published var labBedPrefix = "Lab bed"
    @Published var labTargetURL = "http://edge/"
    @Published var selectedLabSessionID = ""
    @Published var labSessionResponse = RuntimeLabSessionResponse.unavailable(readError: "No Product Lab session has been selected.")
    @Published var labVitalFileUploadSources: [URL] = []
    @Published var labVitalFileImportMessage = ""
    @Published var labVitalFileImportFailed = false
    @Published var labVitalFileReplayResourceMode = RuntimeLabVitalFileReplayResourceMode.quickCreate
    @Published var labVitalFileReplayRepeatMode = RuntimeLabVitalFileReplayRepeatMode.once
    @Published var labVitalFileReplayCount = 2
    @Published var isRunningLabAction = false
    @Published var labActionMessage = ""
    @Published var labActionMessageTone = RuntimeLabActionMessageTone.neutral

    let controlClient: any RuntimeControlClient
    let hostClient: any RuntimeHostClient
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
        initialStatus: PlatformState? = nil,
        healthNotifications: any HealthNotifying = NoopHealthNotifier(),
        nativeShell: any RuntimeNativeShell = NoopRuntimeNativeShell(),
        helperMessageLog: any RuntimeHelperMessageLogging = NoopRuntimeHelperMessageLog()
    ) {
        self.controlClient = controlClient
        self.hostClient = hostClient
        self.helperMessageLog = helperMessageLog
        let loadedSettings = initialSettings ?? controlClient.loadSettings()
        let displaySettings = Self.settingsWithAdvertisedServiceURLPresets(
            loadedSettings,
            fillMissing: initialSettings == nil
        )
        let displayRuntimeSettings = Self.settingsWithAdvertisedServiceURLPresets(
            displaySettings.runtimeAppliedSettings,
            fillMissing: initialSettings == nil
        )
        let resolvedStatus = initialStatus ?? controlClient.loadPlatformState(settings: displayRuntimeSettings)
        let resolvedOperationState = controlClient.loadOperationState()
        self.runtimeSettings = displayRuntimeSettings
        self.savedSettings = displaySettings
        self.settings = displaySettings
        self.platformSettingsReadState = Self.platformSettingsPresentationState(for: loadedSettings)
        self.status = resolvedStatus
        self.operationState = resolvedOperationState
        let snapshots = RuntimePresentationSnapshotLoader(
            controlClient: controlClient,
            hostClient: hostClient,
            snapshotReader: snapshotReader
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

    var canDisplayPlatformSettings: Bool {
        platformSettingsReadState == .loaded
    }

    var platformSettingsReadIssues: [RuntimeSettingsReadIssue] {
        switch platformSettingsReadState {
        case .notRead:
            []
        case .loaded:
            settings.readIssues
        case .failed(let issues):
            issues
        }
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
        isApplyingUpdateBundle || presentationFormatter.updateOperationInProgress(operationState)
    }

    var updateProgressMessage: String {
        if isApplyingUpdateBundle {
            return operationDetail.isEmpty ? message : operationDetail
        }
        return presentationFormatter.updateOperationDisplayMessage(status, operationState: operationState) ?? message
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
        await refreshRuntimeStack()
        await refreshRedisRelayStatus()
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

    func refreshRedisRelayStatus() async {
        do {
            redisRelayStatusRead = try await controlClient.loadRedisRelayStatus()
        } catch {
            redisRelayStatusRead = RuntimeRedisRelayStatusReadResult(
                readState: .readFailed,
                document: nil,
                readError: error.localizedDescription
            )
        }
    }

    func refreshRuntimeStack() async {
        do {
            let stackStatus = try await controlClient.guestStackStatus()
            var resources: [RuntimeGuestServiceResource] = []
            var resourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = []
            let services = Array(Set(stackStatus.services.map(\.service))).sorted()
            for service in services {
                do {
                    resources.append(try await controlClient.guestServiceResource(service))
                } catch {
                    resourceReadIssues.append(
                        RuntimeGuestServiceResourceReadIssue(
                            service: service,
                            message: error.localizedDescription
                        )
                    )
                }
            }
            runtimeStackStatus = stackStatus
            runtimeStackReadError = nil
            runtimeServiceResources = resources
            runtimeServiceResourceReadIssues = resourceReadIssues
        } catch {
            runtimeStackStatus = nil
            runtimeStackReadError = error.localizedDescription
            runtimeServiceResources = []
            runtimeServiceResourceReadIssues = []
        }
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
        guard !Task.isCancelled else {
            return
        }
        vitalDBObservationSnapshot = refreshed.observationSnapshot
        vitalRecorders = refreshed.recorders
        vitalBeds = refreshed.beds
        vitalRelationships = refreshed.relationships
    }

    func relationshipPresentationHistory(
        bedID: String
    ) -> RuntimeVitalRelationshipPresentationHistory {
        vitalRelationshipPresentationIndex.history(bedID: bedID)
    }

    func relationshipPresentationHistory(
        vrcode: String
    ) -> RuntimeVitalRelationshipPresentationHistory {
        vitalRelationshipPresentationIndex.history(vrcode: vrcode)
    }

    func refreshVitalRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async {
        let window = await snapshots.loadVitalRecorderActivityWindow(query: query)
        recorderActivityWindows[recorderActivityWindowKey(query)] = window
    }

    func pollVitalRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery,
        intervalNanoseconds: UInt64 = 5_000_000_000
    ) async {
        while !Task.isCancelled {
            await refreshVitalRecorderActivityWindow(query: query)
            guard !Task.isCancelled else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: intervalNanoseconds)
            } catch {
                return
            }
        }
    }

    func recorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow? {
        recorderActivityWindows[recorderActivityWindowKey(query)]
    }

    func refreshVitalRecorderVitalFiles(vrcode: String) async {
        let history = await snapshots.loadVitalRecorderVitalFiles(vrcode: vrcode)
        guard !Task.isCancelled else {
            return
        }
        recorderVitalFileHistories[vrcode] = history
    }

    func refreshRecorderObservabilityDetail(vrcode: String) async {
        let detail = await snapshots.loadRecorderObservabilityDetail(vrcode: vrcode)
        guard !Task.isCancelled else {
            return
        }
        recorderObservabilityDetails[vrcode] = detail
    }

    func refreshRecorderObservabilityIncidents(
        query: RuntimeRecorderObservabilityIncidentQuery
    ) async {
        let incidents = await snapshots.loadRecorderObservabilityIncidents(query: query)
        guard !Task.isCancelled else {
            return
        }
        recorderObservabilityIncidents[recorderObservabilityIncidentKey(query)] = incidents
    }

    func recorderObservabilityIncidentPage(
        query: RuntimeRecorderObservabilityIncidentQuery
    ) -> RuntimeRecorderObservabilityIncidents? {
        recorderObservabilityIncidents[recorderObservabilityIncidentKey(query)]
    }

    private func recorderObservabilityIncidentKey(
        _ query: RuntimeRecorderObservabilityIncidentQuery
    ) -> String {
        // The panel maintains one fixed recent-history window per Recorder.
        // Keeping this key on the Recorder identity avoids treating a fresh UI
        // render's wall-clock `until` value as a different cached result.
        query.vrcode
    }

    @discardableResult
    func hideVitalDBRecorder(vrcode: String) async -> Bool {
        await runVitalDBVisibilityAction(successMessage: "\(vrcode) hidden from recorder list.") {
            try await controlClient.hideVitalDBRecorders(.init(vrcodes: [vrcode]))
        }
    }

    @discardableResult
    func unhideVitalDBRecorder(vrcode: String) async -> Bool {
        await runVitalDBVisibilityAction(successMessage: "\(vrcode) shown in recorder list.") {
            try await controlClient.unhideVitalDBRecorders(.init(vrcodes: [vrcode]))
        }
    }

    @discardableResult
    func deleteVitalDBRecorder(vrcode: String) async -> Bool {
        await runVitalDBVisibilityAction(successMessage: "\(vrcode) deleted from recorder history.") {
            try await controlClient.deleteVitalDBRecorders(.init(vrcodes: [vrcode]))
        }
    }

    @discardableResult
    func hideVitalDBBed(bedID: String) async -> Bool {
        await runVitalDBBedVisibilityAction(successMessage: "Bed hidden.") {
            try await controlClient.hideVitalDBBeds(.init(bedIDs: [bedID]))
        }
    }

    @discardableResult
    func unhideVitalDBBed(bedID: String) async -> Bool {
        await runVitalDBBedVisibilityAction(successMessage: "Bed visible.") {
            try await controlClient.unhideVitalDBBeds(.init(bedIDs: [bedID]))
        }
    }

    @discardableResult
    func deleteVitalDBBed(bedID: String) async -> Bool {
        await runVitalDBBedVisibilityAction(successMessage: "Hidden bed deleted.") {
            try await controlClient.deleteVitalDBBeds(.init(bedIDs: [bedID]))
        }
    }

    private func runVitalDBVisibilityAction(
        successMessage: String,
        action: () async throws -> RuntimeVitalRecorderHistory
    ) async -> Bool {
        isRunningVitalDBVisibilityAction = true
        vitalDBVisibilityActionMessage = "Updating VitalDB visibility..."
        defer { isRunningVitalDBVisibilityAction = false }
        do {
            vitalRecorders = try await action()
            vitalDBVisibilityActionMessage = successMessage
            return true
        } catch {
            vitalDBVisibilityActionMessage = error.localizedDescription
            return false
        }
    }

    private func runVitalDBBedVisibilityAction(
        successMessage: String,
        action: () async throws -> RuntimeVitalBedHistory
    ) async -> Bool {
        isRunningVitalDBVisibilityAction = true
        vitalDBVisibilityActionMessage = "Updating VitalDB visibility..."
        defer { isRunningVitalDBVisibilityAction = false }
        do {
            let bedHistory = try await action()
            vitalBeds = bedHistory
            vitalDBVisibilityActionMessage = successMessage
            return true
        } catch {
            vitalDBVisibilityActionMessage = error.localizedDescription
            return false
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
        let redisRelaySettingsToApply = settingsToApply.redisRelay
        let redisRelayChanged = redisRelaySettingsToApply != savedSettings.redisRelay
        let applySettingsResult = await runClientAction(
            preparingMessage: AppConstants.StatusText.settingsApplyPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.settingsApplyRunning,
            successMessage: AppConstants.StatusText.settingsApplied,
            action: { try await self.controlClient.applySettings(settingsToApply) }
        )
        if applySettingsResult.isSuccess {
            if redisRelayChanged {
                guard await applyRuntimeRedisRelaySettings(redisRelaySettingsToApply) else {
                    await refreshHealthStatus()
                    return
                }
            }
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
        guard canApplySettingsForCurrentConnection else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        var settingsToActivate = savedSettings
        settingsToActivate.appliedVMSettings = nil
        settingsToActivate.restartAfterSave = false
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.restartVMRuntimePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.restartVMRuntimeRunning,
            successMessage: AppConstants.StatusText.restartVMRuntimeCompleted,
            action: { try await self.controlClient.restartVMRuntime(applying: settingsToActivate) }
        )
        await refresh()
    }

    public func relaunchHelper() {
        nativeShell.relaunchHelper()
    }

    public func reconnectRuntimeControl() {
        message = AppConstants.StatusText.runtimeControlReconnecting
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
        let nextReadState = Self.platformSettingsPresentationState(for: nextSettings)
        platformSettingsReadState = nextReadState
        guard nextReadState == .loaded else {
            return
        }
        var loadedSettings = Self.settingsWithAdvertisedServiceURLPresets(nextSettings, fillMissing: true)
        do {
            let read = try await controlClient.loadRuntimeRedisRelaySettings()
            runtimeRedisRelaySettingsRead = read
            if read.state == .loaded, let document = read.settings {
                loadedSettings.redisRelay = Self.redisRelaySettings(from: document)
            } else {
                loadedSettings.redisRelay = RuntimeRedisRelaySettings()
            }
        } catch {
            runtimeRedisRelaySettingsRead = RuntimeRedisRelaySettingsRead(
                state: .failed,
                settings: nil,
                readError: error.localizedDescription
            )
            loadedSettings.redisRelay = RuntimeRedisRelaySettings()
        }
        runtimeSettings = Self.settingsWithAdvertisedServiceURLPresets(loadedSettings.runtimeAppliedSettings, fillMissing: true)
        savedSettings = loadedSettings
        settings = loadedSettings
    }

    private static func platformSettingsPresentationState(
        for settings: RuntimeSettings
    ) -> RuntimePlatformSettingsPresentationState {
        let ownerIssues = settings.readIssues.filter { $0.source == "platformSettings" }
        guard ownerIssues.isEmpty else {
            return .failed(ownerIssues)
        }
        return .loaded
    }

    var canEditRuntimeRedisRelaySettings: Bool {
        runtimeRedisRelaySettingsRead.state == .loaded
    }

    private func applyRuntimeRedisRelaySettings(_ settings: RuntimeRedisRelaySettings) async -> Bool {
        guard canEditRuntimeRedisRelaySettings else {
            message = runtimeRedisRelaySettingsRead.readError
                ?? "Runtime Redis Relay settings owner is unavailable."
            return false
        }
        do {
            let operation = try await controlClient.applyRuntimeRedisRelaySettings(
                Self.redisRelayApplyRequest(from: settings)
            )
            switch operation.state {
            case .accepted, .running, .completed:
                message = "Redis Relay settings operation \(operation.operationId) is \(operation.state.rawValue)."
                return true
            case .failed, .cancelled, .interrupted:
                message = operation.failure?.message
                    ?? "Redis Relay settings operation \(operation.operationId) \(operation.state.rawValue)."
                return false
            }
        } catch {
            message = "Redis Relay settings apply failed: \(error.localizedDescription)"
            return false
        }
    }

    private static func redisRelaySettings(
        from document: RuntimeRedisRelaySettingsReadDocument
    ) -> RuntimeRedisRelaySettings {
        RuntimeRedisRelaySettings(
            enabled: document.enabled,
            target: RuntimeRedisRelayTarget(
                url: document.target.url,
                username: "",
                password: "",
                clearPassword: false,
                clearUsername: false,
                usernameConfigured: document.target.usernameConfigured,
                passwordConfigured: document.target.passwordConfigured,
                tls: document.target.tls
            ),
            scope: document.scope == .waveformTrendOnly ? .waveformTrendOnly : .vitalReconstruction,
            includeRecorderNetworkContext: document.includeRecorderNetworkContext,
            intervalSeconds: document.intervalSeconds,
            scanCount: document.scanCount
        )
    }

    private static func redisRelayApplyRequest(
        from settings: RuntimeRedisRelaySettings
    ) -> RuntimeRedisRelaySettingsApplyRequest {
        RuntimeRedisRelaySettingsApplyRequest(
            enabled: settings.enabled,
            target: RuntimeRedisRelayTargetApply(
                url: settings.target.url,
                username: settings.target.username,
                password: settings.target.password.isEmpty ? nil : settings.target.password,
                clearPassword: settings.target.clearPassword,
                clearUsername: settings.target.clearUsername,
                tls: settings.target.tls
            ),
            scope: settings.scope == .waveformTrendOnly ? .waveformTrendOnly : .vitalReconstruction,
            includeRecorderNetworkContext: settings.includeRecorderNetworkContext,
            intervalSeconds: settings.intervalSeconds,
            scanCount: settings.scanCount
        )
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
        controlClient.capabilities.canEditRuntimeProviderResources
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
        operationState = result.operationState
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
