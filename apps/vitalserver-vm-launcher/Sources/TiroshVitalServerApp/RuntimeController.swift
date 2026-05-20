import AppKit
import Foundation

@MainActor
final class RuntimeController: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var settings = RuntimeSettings.load()
    @Published var selectedBundlePath = ""
    @Published var selectedBundleSummary = ""
    @Published var backups = RuntimeBackup.loadAll()
    @Published var selectedBackupPath = ""
    @Published var message = AppConstants.StatusText.ready
    @Published var isBusy = false

    private let runtime = RuntimePaths()

    func refresh() async {
        status = RuntimeStatus.load(paths: runtime)
        settings = RuntimeSettings.load()
        backups = RuntimeBackup.loadAll()
        let backupPaths = Set(backups.map(\.path))
        if let latest = backups.first, (selectedBackupPath.isEmpty || !backupPaths.contains(selectedBackupPath)) {
            selectedBackupPath = latest.path
        } else if backups.isEmpty {
            selectedBackupPath = ""
        }
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
    }

    func refreshHealthStatus() async {
        status = await loadHealthStatus()
        if let displayMessage = status.displayMessage {
            message = displayMessage
        }
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        status = await loadHealthStatus()
        if let displayMessage = status.displayMessage {
            message = "\(AppConstants.StatusText.healthCheckCompleted)\n\n\(displayMessage)"
        } else {
            message = AppConstants.StatusText.healthCheckCompleted
        }
    }

    func uninstallRuntime() async {
        let command: String
        if FileManager.default.isExecutableFile(atPath: runtime.uninstaller) {
            command = shellQuote(runtime.uninstaller)
        } else {
            message = AppConstants.StatusText.missingUninstaller
            return
        }

        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.uninstallPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.uninstallRunning,
            successMessage: AppConstants.StatusText.uninstallCompleted
        )
        await refreshHealthStatus()
    }

    func saveSettings() async {
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = shellCommand(
            executable: runtime.launcher,
            arguments: settings.configureArguments()
        )
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: "Preparing runtime settings...",
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: "Saving runtime settings...",
            successMessage: AppConstants.StatusText.settingsSaved
        )
        await refreshHealthStatus()
    }

    func chooseUpdateBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppConstants.Actions.chooseBundle
        if panel.runModal() == .OK, let url = panel.url {
            selectedBundlePath = url.path
            selectedBundleSummary = updateBundleSummary(url: url)
        }
    }

    func applySelectedBundle() async {
        guard !selectedBundlePath.isEmpty else {
            message = AppConstants.StatusText.missingBundle
            return
        }
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = shellCommand(
            executable: runtime.launcher,
            arguments: ["runtime", "apply-bundle", selectedBundlePath]
        )
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: "Preparing update bundle...",
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: "Applying update bundle...",
            successMessage: AppConstants.StatusText.updateBundleApplied
        )
        await refreshHealthStatus()
    }

    func rollbackRuntime() async {
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = shellCommand(
            executable: runtime.launcher,
            arguments: ["runtime", "rollback"] + (selectedBackupPath.isEmpty ? [] : [selectedBackupPath])
        )
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: "Preparing rollback...",
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: "Rolling back runtime...",
            successMessage: AppConstants.StatusText.rollbackCompleted
        )
        await refresh()
        await refreshHealthStatus()
    }

    func openLogs() {
        if FileManager.default.fileExists(atPath: AppConstants.Paths.runtimeLogs) {
            NSWorkspace.shared.open(URL(fileURLWithPath: AppConstants.Paths.runtimeLogs))
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: AppConstants.Paths.installLog))
        }
    }

    func openVitalServer() {
        NSWorkspace.shared.open(URL(string: AppConstants.Product.vitalServerURL(proxyPort: status.proxyPort))!)
    }

    func openRedisUI() {
        NSWorkspace.shared.open(URL(string: AppConstants.Product.redisUIURL(proxyPort: status.proxyPort))!)
    }

    func openSwagger() {
        NSWorkspace.shared.open(URL(string: AppConstants.Product.swaggerURL(proxyPort: status.proxyPort))!)
    }

    private func runPrivileged(
        shellCommand: String,
        preparingMessage: String,
        waitingMessage: String,
        runningMessage: String,
        successMessage: String
    ) async -> Bool {
        isBusy = true
        defer { isBusy = false }

        message = preparingMessage
        try? await Task.sleep(nanoseconds: 200_000_000)
        message = waitingMessage

        let loggedCommand = commandWithLog(shellCommand)
        let script = #"do shell script "\#(appleScriptEscaped(loggedCommand))" with administrator privileges"#
        message = runningMessage
        let result = await ProcessRunner.run(AppConstants.Commands.osascript, arguments: ["-e", script])
        if result.exitCode == 0 {
            message = messageWithLog(title: successMessage, result: result)
            return true
        } else {
            message = messageWithLog(
                title: result.summary.isEmpty ? AppConstants.StatusText.commandCancelled : result.summary,
                result: result
            )
            return false
        }
    }

    private func loadHealthStatus() async -> RuntimeStatus {
        var next = RuntimeStatus.load(paths: runtime)

        if let vmIP = next.vmIP {
            next.guestHTTP = await httpStatus(url: AppConstants.Product.guestHealthURL(vmIP: vmIP))
        }
        next.hostProxyHTTP = await httpStatus(url: AppConstants.Product.hostProxyHealthURL(proxyPort: next.proxyPort))

        return next
    }

    private func httpStatus(url: String) async -> String {
        let result = await ProcessRunner.run(
            AppConstants.Commands.curl,
            arguments: ["-sS", "-I", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 ? code : AppConstants.StatusText.failed
    }

    private func updateBundleSummary(url: URL) -> String {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestURL.path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Missing or invalid manifest.json"
        }
        let version = object["version"] as? String ?? "unknown"
        let artifacts = (object["artifacts"] as? [[String: Any]] ?? [])
            .compactMap { artifact -> String? in
                guard let type = artifact["type"] as? String,
                      let name = artifact["name"] as? String else { return nil }
                return "\(type): \(name)"
            }
            .joined(separator: "\n")
        return "Version: \(version)\nArtifacts:\n\(artifacts)"
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    private func commandWithLog(_ shellCommand: String) -> String {
        let logFile = shellQuote(AppConstants.Paths.commandLogFile)
        let script = [
            "rm -f \(logFile)",
            "{ \(shellCommand); } > \(logFile) 2>&1",
            "status=$?",
            "cat \(logFile)",
            "exit $status"
        ].joined(separator: "; ")
        return "/bin/bash -lc \(shellQuote(script))"
    }

    private func messageWithLog(title: String, result: ProcessResult) -> String {
        let output = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, output != AppConstants.StatusText.done else {
            return title
        }
        return "\(title)\n\n\(output)"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
