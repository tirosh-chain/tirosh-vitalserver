import AppKit
import Foundation
import RuntimeCore

@MainActor
final class RuntimeController: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var settings = RuntimeSettings()
    @Published var selectedBundlePath = ""
    @Published var selectedBundleSummary = ""
    @Published var selectedBundleVerification = ""
    @Published var selectedBundleVerified = false
    @Published var backups: [RuntimeBackup] = []
    @Published var selectedBackupPath = ""
    @Published var message = AppConstants.StatusText.ready
    @Published var operationDetail = ""
    @Published var logText = AppConstants.StatusText.ready
    @Published var logLineLimit = 500
    @Published var selectedLogSource = LogSourceID.helperMessage.rawValue
    @Published var logStreaming = true
    @Published var isBusy = false

    private let runtime = RuntimePaths()
    private let statusReader: RuntimeStatusReading
    private let privilegedCommandRunner: PrivilegedCommandRunning
    private let fileReader: RuntimeManagerFileReading
    private let settingsReader: RuntimeSettingsReading
    private let actionEnvironment: RuntimeActionEnvironment
    private let healthNotifications = HealthNotificationCenter()
    private let logLineLimitOptions = [100, 500, 1000]
    private let logSources: [LogSourceOption] = [
        LogSourceOption(id: LogSourceID.helperMessage.rawValue, title: "Helper message"),
        LogSourceOption(id: LogSourceID.install.rawValue, title: "Install log"),
        LogSourceOption(id: LogSourceID.command.rawValue, title: "Command log"),
        LogSourceOption(id: LogSourceID.launcher.rawValue, title: "VM launcher"),
        LogSourceOption(id: LogSourceID.proxyOutput.rawValue, title: "Host proxy output"),
        LogSourceOption(id: LogSourceID.proxyError.rawValue, title: "Host proxy error"),
        LogSourceOption(id: LogSourceID.updateActivation.rawValue, title: "Update activation"),
        LogSourceOption(id: LogSourceID.containers.rawValue, title: "Containers"),
    ]
    private var healthNotificationBaseline: HealthNotificationState?

    init(
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        privilegedCommandRunner: PrivilegedCommandRunning = SystemPrivilegedCommandRunner(),
        fileReader: RuntimeManagerFileReading = SystemRuntimeManagerFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        actionEnvironment: RuntimeActionEnvironment = SystemRuntimeActionEnvironment()
    ) {
        self.statusReader = statusReader
        self.privilegedCommandRunner = privilegedCommandRunner
        self.fileReader = fileReader
        self.settingsReader = settingsReader
        self.actionEnvironment = actionEnvironment
        self.settings = settingsReader.load()
        healthNotifications.configure()
    }

    var selectedBackup: RuntimeBackup? {
        backups.first { $0.path == selectedBackupPath }
    }

    var selectedBundleConfirmation: String {
        [
            AppConstants.StatusText.updateBundleConfirmation,
            selectedBundlePath,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
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
            "Restart services: \(settings.restartAfterSave ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
        ].joined(separator: "\n")
    }

    func refresh() async {
        settings = settingsReader.load()
        status = statusReader.loadStatus(settings: settings)
        refreshBackupList()
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
        handleHealthNotificationTransition(status)
        refreshLogsIfLive()
    }

    func refreshHealthStatus() async {
        status = await statusReader.loadHealthStatus(settings: settings)
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
        handleHealthNotificationTransition(status)
        refreshLogsIfLive()
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        status = await statusReader.loadHealthStatus(settings: settings)
        if let displayMessage = status.displayMessage {
            message = "\(AppConstants.StatusText.healthCheckCompleted)\n\n\(displayMessage)"
        } else {
            message = AppConstants.StatusText.healthCheckCompleted
        }
        handleHealthNotificationTransition(status)
    }

    func uninstallRuntime(clean: Bool = false) async {
        let command: String
        if actionEnvironment.isExecutable(atPath: runtime.uninstaller) {
            command = RuntimeCommandFactory.uninstallCommand(uninstaller: runtime.uninstaller, clean: clean)
        } else {
            message = AppConstants.StatusText.missingUninstaller
            return
        }

        let didUninstall = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.uninstallPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.uninstallRunning,
            successMessage: clean
                ? AppConstants.StatusText.cleanUninstallCompleted
                : AppConstants.StatusText.uninstallCompleted
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
        guard actionEnvironment.isExecutable(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        guard validateSettings() else {
            return
        }
        var adminPasswordFile: URL?
        if settings.changeAdminPassword {
            do {
                adminPasswordFile = try actionEnvironment.writeAdminPasswordFile(settings.adminPassword)
            } catch {
                message = error.localizedDescription
                return
            }
        }
        defer {
            if let adminPasswordFile {
                actionEnvironment.removeItem(at: adminPasswordFile)
            }
        }
        let command = RuntimeCommandFactory.shellCommand(
            executable: runtime.launcher,
            arguments: settings.configureArguments(adminPasswordFile: adminPasswordFile?.path)
        )
        let didSave = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.settingsApplyPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.settingsApplyRunning,
            successMessage: AppConstants.StatusText.settingsApplied
        )
        if didSave {
            settings.adminPassword = ""
            settings.changeAdminPassword = false
            await waitForAppliedSettings()
        }
        await refreshHealthStatus()
    }

    func chooseVitalFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppConstants.Actions.chooseDirectory
        if panel.runModal() == .OK, let url = panel.url {
            actionEnvironment.createDirectory(at: url)
            settings.vitalFilesDirectory = url.path
        }
    }

    func chooseUpdateBundle() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppConstants.Actions.chooseBundle
        if panel.runModal() == .OK, let url = panel.url {
            selectedBundlePath = url.path
            selectedBundleSummary = fileReader.updateBundleSummary(url: url)
            selectedBundleVerified = false
            selectedBundleVerification = AppConstants.StatusText.updateBundleVerifying
            await verifySelectedBundle()
        }
    }

    func applySelectedBundle() async {
        guard !selectedBundlePath.isEmpty else {
            message = AppConstants.StatusText.missingBundle
            return
        }
        guard selectedBundleVerified else {
            message = AppConstants.StatusText.updateBundleNotVerified
            return
        }
        guard actionEnvironment.isExecutable(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = RuntimeCommandFactory.shellCommand(
            executable: runtime.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.applyBundle,
                selectedBundlePath,
            ]
        )
        let didApply = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.updateBundlePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.updateBundleApplying,
            successMessage: AppConstants.StatusText.updateBundleApplied
        )
        if didApply {
            message = AppConstants.StatusText.updateBundleAppliedRelaunching
            relaunchHelper()
            return
        }
        await refreshHealthStatus()
    }

    func verifySelectedBundle() async {
        guard !selectedBundlePath.isEmpty else {
            selectedBundleVerification = ""
            selectedBundleVerified = false
            message = AppConstants.StatusText.missingBundle
            return
        }
        guard actionEnvironment.isExecutable(atPath: runtime.launcher) else {
            selectedBundleVerification = AppConstants.StatusText.missingLauncher
            selectedBundleVerified = false
            message = AppConstants.StatusText.missingLauncher
            return
        }

        isBusy = true
        defer { isBusy = false }

        message = AppConstants.StatusText.updateBundleVerifying
        let result = await actionEnvironment.verifyBundle(launcher: runtime.launcher, bundlePath: selectedBundlePath)
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
        guard !selectedBackupPath.isEmpty else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        guard actionEnvironment.isExecutable(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = RuntimeCommandFactory.shellCommand(
            executable: runtime.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.rollback,
            ] + (selectedBackupPath.isEmpty ? [] : [selectedBackupPath])
        )
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.rollbackPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.rollbackRunning,
            successMessage: AppConstants.StatusText.rollbackCompleted
        )
        await refresh()
        await refreshHealthStatus()
    }

    func deleteSelectedBackup() async {
        guard !selectedBackupPath.isEmpty else {
            message = AppConstants.StatusText.missingBackup
            return
        }
        guard isManagedBackupPath(selectedBackupPath) else {
            message = AppConstants.StatusText.invalidBackup
            return
        }
        let command = RuntimeCommandFactory.deleteBackupCommand(path: selectedBackupPath)
        let didDelete = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.backupDeletePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.backupDeleteRunning,
            successMessage: AppConstants.StatusText.backupDeleted
        )
        if didDelete {
            selectedBackupPath = ""
            await refresh()
        }
    }

    func repairProxyPort() async {
        let proxyPort = status.proxyPort
        let command = RuntimeCommandFactory.proxyRepairCommand(proxyPort: proxyPort)
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.proxyRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.proxyRepairRunning,
            successMessage: AppConstants.StatusText.proxyRepairCompleted
        )
        await refreshHealthStatus()
    }

    func repairDatastore() async {
        guard actionEnvironment.isExecutable(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = RuntimeCommandFactory.shellCommand(
            executable: runtime.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.repairDatastore,
            ]
        )
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.datastoreRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.datastoreRepairRunning,
            successMessage: AppConstants.StatusText.datastoreRepairCompleted
        )
        await refreshHealthStatus()
    }

    func openLogs() {
        openFolder(fileReader.preferredLogsPath())
    }

    func availableLogLineLimits() -> [Int] {
        logLineLimitOptions
    }

    func availableLogSources() -> [LogSourceOption] {
        logSources
    }

    func refreshLogs() {
        let limit = max(logLineLimit, 1)
        logText = fileReader.logText(
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
        openFolder(settings.vitalFilesDirectory)
    }

    func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func vitalFileFolders() -> [VitalFileFolder] {
        fileReader.vitalFileFolders(root: settings.vitalFilesDirectory)
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
        NSWorkspace.shared.open(url)
    }

    private func relaunchHelper() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppConstants.Commands.shell)
        process.arguments = ["-c", RuntimeCommandFactory.relaunchHelperCommand()]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }

    private func validateSettings() -> Bool {
        if settings.networkMode == AppConstants.Values.networkBridged {
            message = AppConstants.StatusText.bridgedModeUnavailable
            return false
        }
        let installedDiskGiB = settingsReader.load().diskGiB
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
        backups = fileReader.backups(latestBackupPath: status.latestBackup)
        let backupPaths = Set(backups.map(\.path))
        if let latest = backups.first, selectedBackupPath.isEmpty || !backupPaths.contains(selectedBackupPath) {
            selectedBackupPath = latest.path
        } else if backups.isEmpty {
            selectedBackupPath = ""
        }
    }

    private func isManagedBackupPath(_ path: String) -> Bool {
        let backupURL = URL(fileURLWithPath: path).standardizedFileURL
        let backupsURL = URL(fileURLWithPath: AppConstants.Paths.backups).standardizedFileURL
        guard backupURL.lastPathComponent.contains("-before-") else {
            return false
        }
        return backupURL.path.hasPrefix(backupsURL.path + "/")
    }

    private func runPrivileged(
        shellCommand: String,
        preparingMessage: String,
        waitingMessage: String,
        runningMessage: String,
        successMessage: String
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

        selectedLogSource = LogSourceID.command.rawValue
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

        let result = await privilegedCommandRunner.run(shellCommand: shellCommand)
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
        status = statusReader.loadStatus(settings: settings)
        operationDetail = status.progressDisplayMessage ?? statusReader.legacyCommandProgressLine() ?? fallback
    }

    private func quitAfterSuccessfulUninstall() async {
        message = [
            message,
            AppConstants.StatusText.applicationWillQuit,
        ].joined(separator: "\n\n")
        try? await Task.sleep(nanoseconds: 800_000_000)
        NSApplication.shared.terminate(nil)
    }

    private func waitForAppliedSettings() async {
        for _ in 0..<12 {
            settings = settingsReader.load()
            status = await statusReader.loadHealthStatus(settings: settings)
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

struct LogSourceOption: Identifiable {
    let id: String
    let title: String
}

enum LogSourceID: String {
    case helperMessage
    case install
    case command
    case launcher
    case proxyOutput
    case proxyError
    case updateActivation
    case containers
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
