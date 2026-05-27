import Foundation
import MacHostRuntimeAdapter
import RuntimeControl
import Contracts

@MainActor
final class RuntimeViewModel: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var settings = RuntimeSettings()
    @Published var selectedBundleURL: URL?
    @Published var selectedBundleSummary = ""
    @Published var selectedBundleVerification = ""
    @Published var selectedBundleVerified = false
    @Published var backups: [RuntimeBackup] = []
    @Published var selectedBackupPath = ""
    @Published var message = AppConstants.StatusText.ready
    @Published var operationDetail = ""
    @Published var logText = AppConstants.StatusText.ready
    @Published var logLineLimit = 500
    @Published var selectedLogSource = RuntimeLogSource.helperMessage
    @Published var logStreaming = true
    @Published var useCustomAdvertisedURL = false
    @Published var isBusy = false
    @Published var isApplyingUpdateBundle = false
    @Published var isCreatingRedisBackup = false
    var isRefreshingLogs = false
    @Published var releaseInfo = RuntimeReleaseInfo.generated
    @Published var installationInfo = RuntimeInstallInfo()
    @Published var runtimeEvents = RuntimeEventHistory(events: [])
    @Published var vitalRecorders = RuntimeVitalRecorderHistory()
    @Published var vitalRelationships = RuntimeVitalRelationshipHistory()
    @Published var containerObservation: RuntimeContainerObservation?
    @Published var testKitStatus = RuntimeTestKitStatus(enabled: false, state: .disabled)
    @Published var selectedTestKitSessionID = ""
    @Published var testKitVrcode = RuntimeViewModel.generatedTestKitVrcode()
    @Published var testKitOrphanVrcode = ""
    @Published var testKitScenario = RuntimeTestKitScenario.normal
    @Published var testKitSignalProfile = RuntimeTestKitSignalProfile.normal
    @Published var testKitRecorderCount = 1
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
    private let readWorker: MacHostRuntimeReadWorker?
    private let healthNotifications: any HealthNotifying
    private let healthNotificationCoordinator: RuntimeHealthNotificationCoordinator
    let nativeShell: any RuntimeNativeShell
    let backupSelectionPolicy = RuntimeBackupSelectionPolicy()
    let processMessageFormatter = RuntimeProcessMessageFormatter()
    let presentationFormatter = RuntimePresentationFormatter()
    private let settingsValidator = RuntimeSettingsValidator()
    private let vitalFilesDirectoryPolicy = RuntimeVitalFilesDirectoryPolicy()

    init(
        controlClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        testKitController: (any RuntimeTestKitControlling)? = nil,
        readWorker: MacHostRuntimeReadWorker? = nil,
        initialSettings: RuntimeSettings? = nil,
        healthNotifications: any HealthNotifying = HealthNotificationCenter(),
        nativeShell: any RuntimeNativeShell = SystemRuntimeNativeShell()
    ) {
        self.controlClient = controlClient
        self.hostClient = hostClient
        self.testKitController = testKitController
        self.readWorker = readWorker
        self.healthNotifications = healthNotifications
        self.healthNotificationCoordinator = RuntimeHealthNotificationCoordinator(notifier: self.healthNotifications)
        self.nativeShell = nativeShell
        let initialSettings = initialSettings ?? self.controlClient.loadSettings()
        self.settings = initialSettings
        self.useCustomAdvertisedURL = Self.usesCustomAdvertisedURL(initialSettings)
        self.installationInfo = self.controlClient.loadInstallInfo()
        self.healthNotifications.configure()
    }

    var capabilities: RuntimeControlCapabilities {
        controlClient.capabilities
    }

    var selectedBundleConfirmation: String {
        presentationFormatter.selectedBundleConfirmation(bundlePath: selectedBundlePath)
    }

    var selectedBundlePath: String {
        selectedBundleURL?.path ?? ""
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
        status = await loadStatusSnapshot(settings: settings)
        await refreshReleaseInfo()
        await refreshBackupList()
        await refreshRuntimeEvents()
        await refreshVitalRecorders()
        if let displayMessage = presentationFormatter.statusDisplayMessage(status) {
            message = displayMessage
        }
        synchronizeFileBackedOperationPresentation()
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func refreshHealthStatus() async {
        status = await loadHealthStatusSnapshot(settings: settings)
        if let displayMessage = presentationFormatter.statusDisplayMessage(status) {
            message = displayMessage
        }
        synchronizeFileBackedOperationPresentation()
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        status = await loadHealthStatusSnapshot(settings: settings)
        await refreshRuntimeEvents()
        await refreshVitalRecorders()
        if let displayMessage = presentationFormatter.statusDisplayMessage(status) {
            message = "\(AppConstants.StatusText.healthCheckCompleted)\n\n\(displayMessage)"
        } else {
            message = AppConstants.StatusText.healthCheckCompleted
        }
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func refreshRuntimeEvents(limit: Int = 100) async {
        runtimeEvents = await loadRuntimeEventsSnapshot(limit: limit)
        containerObservation = status.containerObservation
            ?? runtimeEvents.events.first { $0.containerObservation != nil }?.containerObservation
    }

    func refreshVitalRecorders() async {
        async let recorders = loadVitalRecordersSnapshot()
        async let relationships = loadVitalRelationshipsSnapshot()
        let snapshots = await (recorders, relationships)
        vitalRecorders = snapshots.0
        vitalRelationships = snapshots.1
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

    func setCustomAdvertisedURL(_ enabled: Bool) {
        useCustomAdvertisedURL = enabled
        normalizeAdvertisedURLSettings()
    }

    func syncAdvertisedURLWithProxyIfNeeded() {
        normalizeAdvertisedURLSettings()
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

    func relaunchHelper() {
        nativeShell.relaunchHelper()
    }

    private func validateSettings() -> Bool {
        let result = settingsValidator.validate(settings, installedSettings: controlClient.loadSettings())
        if case .invalid(let validationMessage) = result {
            message = validationMessage
        }
        return result.isValid
    }

    private func loadRuntimeSettings() async {
        let nextSettings = await loadSettingsSnapshot()
        settings = nextSettings
        useCustomAdvertisedURL = Self.usesCustomAdvertisedURL(nextSettings)
    }

    private func normalizeAdvertisedURLSettings() {
        guard !useCustomAdvertisedURL else {
            return
        }
        settings.publicHost = ""
        settings.publicPort = settings.proxyPort
    }

    private static func usesCustomAdvertisedURL(_ settings: RuntimeSettings) -> Bool {
        !settings.publicHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || settings.publicPort != settings.proxyPort
    }

    func refreshBackupList() async {
        backups = await loadBackupsSnapshot(latestBackupPath: status.latestBackup)
        selectedBackupPath = backupSelectionPolicy.selectedBackupPath(
            from: backups,
            currentSelection: selectedBackupPath
        )
    }

    private func refreshReleaseInfo() async {
        guard controlClient.capabilities.canViewReleaseMetadata else {
            return
        }
        if let loaded = try? await controlClient.loadReleaseInfo() {
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
        isBusy = true
        defer {
            isBusy = false
            operationDetail = ""
        }

        message = preparingMessage
        operationDetail = preparingMessage
        try? await Task.sleep(nanoseconds: 200_000_000)
        message = waitingMessage
        operationDetail = waitingMessage

        if refreshCommandLog {
            selectedLogSource = .command
            await refreshLogs()
        }
        message = runningMessage
        operationDetail = runningMessage
        let logRefreshTask = refreshCommandLog
            ? Task { @MainActor in
                while !Task.isCancelled {
                    await refreshLogs()
                    await refreshOperationDetail(fallback: runningMessage)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            : nil
        defer {
            logRefreshTask?.cancel()
            if refreshCommandLog {
                Task { @MainActor in
                    await refreshLogs()
                }
            }
        }

        let result: RuntimeCommandResult
        do {
            result = try await action()
        } catch {
            message = error.localizedDescription
            operationDetail = error.localizedDescription
            return false
        }
        if result.exitCode == 0 {
            message = processMessageFormatter.message(title: successMessage, result: result)
            operationDetail = successMessage
            return true
        } else {
            let failureSummary = processMessageFormatter.summary(result)
            message = processMessageFormatter.message(
                title: failureSummary.isEmpty ? AppConstants.StatusText.commandCancelled : failureSummary,
                result: result
            )
            operationDetail = AppConstants.StatusText.commandCancelled
            return false
        }
    }

    private func refreshOperationDetail(fallback: String) async {
        status = await loadStatusSnapshot(settings: settings)
        if let progressMessage = presentationFormatter.progressDisplayMessage(status) {
            operationDetail = progressMessage
            return
        }
        operationDetail = await legacyCommandProgressLineSnapshot() ?? fallback
    }

    private func synchronizeFileBackedOperationPresentation() {
        guard !isBusy,
              let updateMessage = presentationFormatter.updateOperationDisplayMessage(status) else {
            return
        }
        selectedLogSource = .command
        message = updateMessage
        operationDetail = updateMessage
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
            status = await loadHealthStatusSnapshot(settings: settings)
            await refreshLogsIfLive()
            if status.isReady || !settings.restartAfterSave {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func loadSettingsSnapshot() async -> RuntimeSettings {
        if let readWorker {
            return await readWorker.loadSettings()
        }
        return controlClient.loadSettings()
    }

    private func loadStatusSnapshot(settings: RuntimeSettings) async -> RuntimeStatus {
        if let readWorker {
            return await readWorker.loadStatus(settings: settings)
        }
        return controlClient.loadStatus(settings: settings)
    }

    private func loadHealthStatusSnapshot(settings: RuntimeSettings) async -> RuntimeStatus {
        if let readWorker {
            return await readWorker.loadHealthStatus(settings: settings)
        }
        return await controlClient.loadHealthStatus(settings: settings)
    }

    private func loadRuntimeEventsSnapshot(limit: Int) async -> RuntimeEventHistory {
        if let readWorker {
            return await readWorker.loadRuntimeEvents(limit: limit)
        }
        return controlClient.loadRuntimeEvents(limit: limit)
    }

    private func loadVitalRecordersSnapshot() async -> RuntimeVitalRecorderHistory {
        if let readWorker {
            return await readWorker.loadVitalDBRecorders()
        }
        return controlClient.loadVitalDBRecorders()
    }

    private func loadVitalRelationshipsSnapshot() async -> RuntimeVitalRelationshipHistory {
        if let readWorker {
            return await readWorker.loadVitalDBRelationships()
        }
        return controlClient.loadVitalDBRelationships()
    }

    private func loadBackupsSnapshot(latestBackupPath: String?) async -> [RuntimeBackup] {
        if let readWorker {
            return await readWorker.loadBackups(latestBackupPath: latestBackupPath)
        }
        return hostClient.loadBackups(latestBackupPath: latestBackupPath)
    }

    private func legacyCommandProgressLineSnapshot() async -> String? {
        if let readWorker {
            return await readWorker.legacyCommandProgressLine()
        }
        return hostClient.legacyCommandProgressLine()
    }

}

enum RuntimeViewModelError: LocalizedError {
    case invalidAdminPassword
    case adminPasswordFileCreateFailed

    var errorDescription: String? {
        switch self {
        case .invalidAdminPassword:
            return "Admin password reset value is invalid."
        case .adminPasswordFileCreateFailed:
            return "Could not prepare admin password reset file."
        }
    }
}
