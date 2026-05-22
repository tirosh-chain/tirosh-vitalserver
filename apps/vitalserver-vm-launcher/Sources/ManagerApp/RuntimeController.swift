import Foundation
import RuntimeCore

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

    private let runtimeClient: any RuntimeClient
    private let healthNotifications: any HealthNotifying
    private let nativeShell: any RuntimeNativeShell
    private let logLineLimitOptions = [100, 500, 1000]
    private let logSources: [LogSourceOption] = [
        LogSourceOption(id: .helperMessage, title: "Helper message"),
        LogSourceOption(id: .install, title: "Install log"),
        LogSourceOption(id: .command, title: "Command log"),
        LogSourceOption(id: .launcher, title: "VM launcher"),
        LogSourceOption(id: .proxyOutput, title: "Host proxy output"),
        LogSourceOption(id: .proxyError, title: "Host proxy error"),
        LogSourceOption(id: .updateActivation, title: "Update activation"),
        LogSourceOption(id: .containers, title: "Containers"),
    ]
    private var healthNotificationBaseline: HealthNotificationState?

    init(
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        privilegedCommandRunner: PrivilegedCommandRunning = SystemPrivilegedCommandRunner(),
        fileReader: RuntimeManagerFileReading = SystemRuntimeManagerFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        actionEnvironment: RuntimeActionEnvironment = SystemRuntimeActionEnvironment(),
        runtimeClient: (any RuntimeClient)? = nil,
        healthNotifications: (any HealthNotifying)? = nil,
        nativeShell: (any RuntimeNativeShell)? = nil
    ) {
        self.runtimeClient = runtimeClient ?? LocalRuntimeClient(
            statusReader: statusReader,
            fileReader: fileReader,
            settingsReader: settingsReader,
            privilegedCommandRunner: privilegedCommandRunner,
            actionEnvironment: actionEnvironment
        )
        self.healthNotifications = healthNotifications ?? HealthNotificationCenter()
        self.nativeShell = nativeShell ?? SystemRuntimeNativeShell()
        self.settings = self.runtimeClient.loadSettings()
        self.healthNotifications.configure()
    }

    var selectedBackup: RuntimeBackup? {
        guard let selectedBackupURL else {
            return nil
        }
        return backups.first { $0.url == selectedBackupURL }
    }

    var capabilities: RuntimeClientCapabilities {
        runtimeClient.capabilities
    }

    var selectedBundleConfirmation: String {
        [
            AppConstants.StatusText.updateBundleConfirmation,
            selectedBundlePath,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    var selectedBundlePath: String {
        selectedBundleURL?.path ?? ""
    }

    var selectedBackupPath: String {
        selectedBackupURL?.path ?? ""
    }

    var applySettingsConfirmation: String {
        [
            AppConstants.StatusText.applySettingsConfirmation,
            "Proxy port: \(settings.proxyPort)",
            "Public host: \(settings.publicHost.isEmpty ? "(same host)" : settings.publicHost)",
            "Public port: \(settings.publicPort)",
            "Network mode: \(settings.networkMode)",
            "Disk size: \(settings.diskGiB) GiB",
            "Vital files directory: \(settings.vitalFilesDirectory)",
            "Automatic recovery: \(settings.autoRecoveryEnabled ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
            "Restart services: \(settings.restartAfterSave ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
        ].joined(separator: "\n")
    }

    func refresh() async {
        settings = runtimeClient.loadSettings()
        status = runtimeClient.loadStatus(settings: settings)
        await refreshReleaseInfo()
        refreshBackupList()
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
        handleHealthNotificationTransition(status)
        refreshLogsIfLive()
    }

    func refreshHealthStatus() async {
        status = await runtimeClient.loadHealthStatus(settings: settings)
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
        handleHealthNotificationTransition(status)
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
        handleHealthNotificationTransition(status)
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

    func chooseUpdateBundle() async {
        guard runtimeClient.capabilities.canApplyBundle else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        if let url = nativeShell.chooseUpdateBundle(prompt: AppConstants.Actions.chooseBundle) {
            selectedBundleURL = url
            selectedBundleSummary = runtimeClient.updateBundleSummary(url: url)
            selectedBundleVerified = false
            selectedBundleVerification = AppConstants.StatusText.updateBundleVerifying
            await verifySelectedBundle()
        }
    }

    func applySelectedBundle() async {
        guard runtimeClient.capabilities.canApplyBundle else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let bundleURL = selectedBundleURL else {
            message = AppConstants.StatusText.missingBundle
            return
        }
        guard selectedBundleVerified else {
            message = AppConstants.StatusText.updateBundleNotVerified
            return
        }
        let didApply = await runClientAction(
            preparingMessage: AppConstants.StatusText.updateBundlePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.updateBundleApplying,
            successMessage: AppConstants.StatusText.updateBundleApplied,
            action: { try await self.runtimeClient.applyUpdateBundle(url: bundleURL) }
        )
        if didApply {
            message = AppConstants.StatusText.updateBundleAppliedRelaunching
            relaunchHelper()
            return
        }
        await refreshHealthStatus()
    }

    func verifySelectedBundle() async {
        guard runtimeClient.capabilities.canApplyBundle else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let bundleURL = selectedBundleURL else {
            selectedBundleVerification = ""
            selectedBundleVerified = false
            message = AppConstants.StatusText.missingBundle
            return
        }

        isBusy = true
        defer { isBusy = false }

        message = AppConstants.StatusText.updateBundleVerifying
        let result: ProcessResult
        do {
            result = try await runtimeClient.verifyUpdateBundle(url: bundleURL)
        } catch {
            selectedBundleVerification = error.localizedDescription
            selectedBundleVerified = false
            message = error.localizedDescription
            return
        }
        if result.exitCode == 0 {
            selectedBundleVerified = true
            selectedBundleVerification = messageWithLog(
                title: AppConstants.StatusText.updateBundleVerified,
                result: result
            )
            message = selectedBundleVerification
        } else {
            selectedBundleVerified = false
            selectedBundleVerification = messageWithLog(
                title: AppConstants.StatusText.updateBundleVerificationFailed,
                result: result
            )
            message = selectedBundleVerification
        }
    }

    func rollbackRuntime() async {
        guard runtimeClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let backupURL = selectedBackupURL else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        _ = await runClientAction(
            preparingMessage: AppConstants.StatusText.rollbackPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.rollbackRunning,
            successMessage: AppConstants.StatusText.rollbackCompleted,
            action: { try await self.runtimeClient.rollbackRuntime(backupURL: backupURL) }
        )
        await refresh()
        await refreshHealthStatus()
    }

    func deleteSelectedBackup() async {
        guard runtimeClient.capabilities.canRollback else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let backupURL = selectedBackupURL else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        guard isManagedBackupURL(backupURL) else {
            message = AppConstants.StatusText.invalidBackup
            return
        }
        let didDelete = await runClientAction(
            preparingMessage: AppConstants.StatusText.backupDeletePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.backupDeleteRunning,
            successMessage: AppConstants.StatusText.backupDeleted,
            action: { try await self.runtimeClient.deleteBackup(url: backupURL) }
        )
        if didDelete {
            selectedBackupURL = nil
            await refresh()
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

    func openLogs() {
        guard runtimeClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(runtimeClient.preferredLogsPath())
    }

    func exportLogs() async {
        guard runtimeClient.capabilities.canExportLogs else {
            message = AppConstants.StatusText.logExportUnavailable
            return
        }
        let defaultName = "vitalserver-logs-\(logExportTimestamp()).zip"
        guard let destination = nativeShell.chooseLogExportDestination(
            defaultName: defaultName,
            prompt: AppConstants.Actions.exportLogs
        ) else {
            return
        }

        isBusy = true
        defer { isBusy = false }
        message = AppConstants.StatusText.logExportPreparing

        do {
            let result = try await runtimeClient.exportLogs(to: destination)
            message = "\(AppConstants.StatusText.logExportCompleted)\n\n\(result.destination.path)"
        } catch {
            message = "\(AppConstants.StatusText.logExportFailed)\n\n\(error.localizedDescription)"
        }
    }

    func availableLogLineLimits() -> [Int] {
        logLineLimitOptions
    }

    func availableLogSources() -> [LogSourceOption] {
        logSources
    }

    func refreshLogs() {
        let limit = max(logLineLimit, 1)
        logText = runtimeClient.logText(
            sourceID: selectedLogSource,
            helperMessage: message,
            lineLimit: limit
        )
    }

    func refreshLogsIfLive() {
        if logStreaming {
            refreshLogs()
        }
    }

    func openVitalFilesDirectory() {
        guard runtimeClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(settings.vitalFilesDirectory)
    }

    func openFolder(_ path: String) {
        nativeShell.openFileURL(URL(fileURLWithPath: path))
    }

    func vitalFileFolders() -> [VitalFileFolder] {
        runtimeClient.vitalFileFolders(root: settings.vitalFilesDirectory)
    }

    func openVitalServer() {
        openRuntimeURL(AppConstants.Product.vitalServerURL(proxyPort: status.proxyPort))
    }

    func openRedisUI() {
        openRuntimeURL(AppConstants.Product.redisUIURL(proxyPort: status.proxyPort))
    }

    func openSwagger() {
        openRuntimeURL(AppConstants.Product.swaggerURL(proxyPort: status.proxyPort))
    }

    func openTiroshWebsite() {
        openRuntimeURL(AppConstants.Product.tiroshURL)
    }

    private func openRuntimeURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        nativeShell.openWebURL(url)
    }

    private func relaunchHelper() {
        nativeShell.relaunchHelper()
    }

    private func logExportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func validateSettings() -> Bool {
        if settings.networkMode == AppConstants.Values.networkBridged {
            message = AppConstants.StatusText.bridgedModeUnavailable
            return false
        }
        let installedDiskGiB = runtimeClient.loadSettings().diskGiB
        if settings.diskGiB < installedDiskGiB {
            message = AppConstants.StatusText.diskDecreaseUnavailable
            return false
        }
        if !(1...65_535).contains(settings.proxyPort) || !(1...65_535).contains(settings.publicPort) {
            message = AppConstants.StatusText.invalidPort
            return false
        }
        if settings.vitalFilesDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !settings.vitalFilesDirectory.hasPrefix("/") {
            message = AppConstants.StatusText.vitalFilesDirectoryRequired
            return false
        }
        if settings.changeAdminPassword, settings.adminPassword.isEmpty {
            message = AppConstants.StatusText.adminPasswordRequired
            return false
        }
        if settings.changeAdminPassword, !isLineSafe(settings.adminPassword) {
            message = AppConstants.StatusText.adminPasswordNewline
            return false
        }
        return true
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private func refreshBackupList() {
        backups = runtimeClient.loadBackups(latestBackupPath: status.latestBackup)
        let backupURLs = Set(backups.map(\.url))
        if let selectedBackupURL, backupURLs.contains(selectedBackupURL) {
            return
        }
        if let latest = backups.first {
            selectedBackupURL = latest.url
        } else if backups.isEmpty {
            selectedBackupURL = nil
        }
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

    private func isManagedBackupURL(_ url: URL) -> Bool {
        let backupURL = url.standardizedFileURL
        let backupsURL = URL(fileURLWithPath: AppConstants.Paths.backups).standardizedFileURL
        guard backupURL.lastPathComponent.contains("-before-") else {
            return false
        }
        return backupURL.path.hasPrefix(backupsURL.path + "/")
    }

    private func runClientAction(
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
            message = messageWithLog(title: successMessage, result: result)
            operationDetail = successMessage
            return true
        } else {
            message = messageWithLog(
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

    private func messageWithLog(title: String, result: ProcessResult) -> String {
        let output = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, output != AppConstants.StatusText.done else {
            return title
        }
        return "\(title)\n\n\(output)"
    }

    private func handleHealthNotificationTransition(_ status: RuntimeStatus) {
        let next = HealthNotificationState(status: status)
        guard let previous = healthNotificationBaseline else {
            healthNotificationBaseline = next
            return
        }
        guard previous != next else {
            return
        }
        healthNotificationBaseline = next

        switch next {
        case .critical:
            healthNotifications.notify(
                title: AppConstants.Notifications.criticalTitle,
                body: status.displayMessage ?? AppConstants.Notifications.criticalBody
            )
        case .needsAttention:
            healthNotifications.notify(
                title: AppConstants.Notifications.needsAttentionTitle,
                body: status.displayMessage ?? AppConstants.Notifications.needsAttentionBody
            )
        case .healthy where previous == .critical || previous == .needsAttention:
            healthNotifications.notify(
                title: AppConstants.Notifications.recoveredTitle,
                body: AppConstants.Notifications.recoveredBody
            )
        default:
            break
        }
    }
}

struct VitalFileFolder: Identifiable {
    var id: String { path }
    let name: String
    let path: String
}

private enum HealthNotificationState: Equatable {
    case healthy
    case needsAttention
    case critical
    case starting
    case notInstalled

    init(status: RuntimeStatus) {
        if status.isReady {
            self = .healthy
        } else if !status.runtimeInstalled {
            self = .notInstalled
        } else if status.runtimeState == AppConstants.Values.stateCritical {
            self = .critical
        } else if status.runtimeState == AppConstants.Values.stateDegraded
            || status.runtimeState == AppConstants.Values.stateRecovering
            || !status.failureReasons.isEmpty {
            self = .needsAttention
        } else {
            self = .starting
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
