import Foundation
import RuntimeControl
import RuntimeCore
import RuntimeContracts

@MainActor
final class RuntimeController: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var settings = RuntimeSettings()
    @Published var selectedBundleURL: URL?
    @Published var selectedBundleSummary = ""
    @Published var selectedBundleVerification = ""
    @Published var selectedBundleVerified = false
    @Published var backups: [RuntimeBackup] = []
    @Published var selectedBackupURL: URL?
    @Published var message = AppConstants.StatusText.ready
    @Published var operationDetail = ""
    @Published var logText = AppConstants.StatusText.ready
    @Published var logLineLimit = 500
    @Published var selectedLogSource = LogSourceID.helperMessage
    @Published var logStreaming = true
    @Published var isBusy = false
    @Published var releaseInfo = RuntimeReleaseInfo.generated
    @Published var installationInfo = RuntimeInstallationInfo()

    let runtimeClient: any RuntimeClient
    private let healthNotifications: any HealthNotifying
    private let healthNotificationCoordinator: RuntimeHealthNotificationCoordinator
    let nativeShell: any RuntimeNativeShell
    let backupSelectionPolicy = RuntimeBackupSelectionPolicy()
    let processMessageFormatter = RuntimeProcessMessageFormatter()
    let presentationFormatter = RuntimePresentationFormatter()
    private let settingsValidator = RuntimeSettingsValidator()

    init(
        runtimeClient: any RuntimeClient,
        healthNotifications: any HealthNotifying = HealthNotificationCenter(),
        nativeShell: any RuntimeNativeShell = SystemRuntimeNativeShell()
    ) {
        self.runtimeClient = runtimeClient
        self.healthNotifications = healthNotifications
        self.healthNotificationCoordinator = RuntimeHealthNotificationCoordinator(notifier: self.healthNotifications)
        self.nativeShell = nativeShell
        self.settings = self.runtimeClient.loadSettings()
        self.installationInfo = self.runtimeClient.loadInstallationInfo()
        self.healthNotifications.configure()
    }

    var capabilities: RuntimeClientCapabilities {
        runtimeClient.capabilities
    }

    var selectedBundleConfirmation: String {
        presentationFormatter.selectedBundleConfirmation(bundlePath: selectedBundlePath)
    }

    var selectedBundlePath: String {
        selectedBundleURL?.path ?? ""
    }

    var selectedBackupPath: String {
        selectedBackupURL?.path ?? ""
    }

    var applySettingsConfirmation: String {
        presentationFormatter.applySettingsConfirmation(settings: settings)
    }

    func refresh() async {
        settings = runtimeClient.loadSettings()
        status = runtimeClient.loadStatus(settings: settings)
        await refreshReleaseInfo()
        refreshBackupList()
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
        healthNotificationCoordinator.handleTransition(to: status)
        refreshLogsIfLive()
    }

    func refreshHealthStatus() async {
        status = await runtimeClient.loadHealthStatus(settings: settings)
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
        healthNotificationCoordinator.handleTransition(to: status)
        refreshLogsIfLive()
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        status = await runtimeClient.loadHealthStatus(settings: settings)
        if let displayMessage = status.displayMessage {
            message = "\(AppConstants.StatusText.healthCheckCompleted)\n\n\(displayMessage)"
        } else {
            message = AppConstants.StatusText.healthCheckCompleted
        }
        healthNotificationCoordinator.handleTransition(to: status)
    }

    func uninstallRuntime(clean: Bool = false) async {
        guard runtimeClient.capabilities.canUninstallRuntime else {
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
            action: { try await self.runtimeClient.uninstallRuntime(clean: clean) }
        )
        if didUninstall {
            await quitAfterSuccessfulUninstall()
        } else {
            await refreshHealthStatus()
        }
    }

    func prepareApplySettings() -> Bool {
        validateSettings()
    }

    func applySettings() async {
        guard canApplySettingsForCurrentConnection else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard validateSettings() else {
            return
        }
        let settingsToApply = settings
        let didSave = await runClientAction(
            preparingMessage: AppConstants.StatusText.settingsApplyPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.settingsApplyRunning,
            successMessage: AppConstants.StatusText.settingsApplied,
            action: { try await self.runtimeClient.applySettings(settingsToApply) }
        )
        if didSave {
            settings.adminPassword = ""
            settings.changeAdminPassword = false
            await waitForAppliedSettings()
        }
        await refreshHealthStatus()
    }

    func chooseVitalFilesDirectory() {
        guard runtimeClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        if let url = nativeShell.chooseDirectory(prompt: AppConstants.Actions.chooseDirectory) {
            runtimeClient.createDirectory(at: url)
            settings.vitalFilesDirectory = url.path
        }
    }

    func repairProxyPort() async {
        guard runtimeClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        let proxyPort = status.proxyPort
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.proxyRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.proxyRepairRunning,
            successMessage: AppConstants.StatusText.proxyRepairCompleted,
            action: { try await self.runtimeClient.repairProxy(proxyPort: proxyPort) }
        )
        await refreshHealthStatus()
    }

    func repairDatastore() async {
        guard runtimeClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.datastoreRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.datastoreRepairRunning,
            successMessage: AppConstants.StatusText.datastoreRepairCompleted,
            action: { try await self.runtimeClient.repairDatastore() }
        )
        await refreshHealthStatus()
    }

    func startRuntimeServices() async {
        guard runtimeClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeServicesStartPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeServicesStartRunning,
            successMessage: AppConstants.StatusText.runtimeServicesStarted,
            action: { try await self.runtimeClient.startRuntimeServices() }
        )
        await refreshHealthStatus()
    }

    func stopRuntimeServices() async {
        guard runtimeClient.capabilities.canControlRuntimeServices else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.runtimeServicesStopPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.runtimeServicesStopRunning,
            successMessage: AppConstants.StatusText.runtimeServicesStopped,
            action: { try await self.runtimeClient.stopRuntimeServices() }
        )
        await refresh()
    }

    func relaunchHelper() {
        nativeShell.relaunchHelper()
    }

    private func validateSettings() -> Bool {
        let result = settingsValidator.validate(settings, installedSettings: runtimeClient.loadSettings())
        if case .invalid(let validationMessage) = result {
            message = validationMessage
        }
        return result.isValid
    }

    func refreshBackupList() {
        backups = runtimeClient.loadBackups(latestBackupPath: status.latestBackup)
        selectedBackupURL = backupSelectionPolicy.selectedBackupURL(
            from: backups,
            currentSelection: selectedBackupURL
        )
    }

    private func refreshReleaseInfo() async {
        guard runtimeClient.capabilities.canViewReleaseMetadata else {
            return
        }
        if let loaded = try? await runtimeClient.loadReleaseInfo() {
            releaseInfo = loaded
        }
    }

    private var canApplySettingsForCurrentConnection: Bool {
        runtimeClient.capabilities.canEditVMResources
            || runtimeClient.capabilities.canEditNetworkExposure
            || runtimeClient.capabilities.canOpenLocalFiles
            || runtimeClient.capabilities.canResetAdminPassword
    }

    func runClientAction(
        preparingMessage: String,
        waitingMessage: String,
        runningMessage: String,
        successMessage: String,
        action: @escaping () async throws -> ProcessResult
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

        selectedLogSource = .command
        refreshLogs()
        message = runningMessage
        operationDetail = runningMessage
        let logRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshLogs()
                refreshOperationDetail(fallback: runningMessage)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        defer {
            logRefreshTask.cancel()
            refreshLogs()
        }

        let result: ProcessResult
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
            message = processMessageFormatter.message(
                title: result.summary.isEmpty ? AppConstants.StatusText.commandCancelled : result.summary,
                result: result
            )
            operationDetail = AppConstants.StatusText.commandCancelled
            return false
        }
    }

    private func refreshOperationDetail(fallback: String) {
        status = runtimeClient.loadStatus(settings: settings)
        operationDetail = status.progressDisplayMessage ?? runtimeClient.legacyCommandProgressLine() ?? fallback
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
            settings = runtimeClient.loadSettings()
            status = await runtimeClient.loadHealthStatus(settings: settings)
            refreshLogsIfLive()
            if status.isReady || !settings.restartAfterSave {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

}

enum RuntimeControllerError: LocalizedError {
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
