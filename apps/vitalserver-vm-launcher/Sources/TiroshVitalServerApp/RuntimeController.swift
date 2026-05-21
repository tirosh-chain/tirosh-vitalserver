import AppKit
import Foundation

@MainActor
final class RuntimeController: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var settings = RuntimeSettings.load()
    @Published var selectedBundlePath = ""
    @Published var selectedBundleSummary = ""
    @Published var selectedBundleVerification = ""
    @Published var selectedBundleVerified = false
    @Published var backups = RuntimeBackup.loadAll()
    @Published var selectedBackupPath = ""
    @Published var message = AppConstants.StatusText.ready
    @Published var isBusy = false

    private let runtime = RuntimePaths()

    var selectedBundleConfirmation: String {
        [
            selectedBundleSummary.isEmpty ? selectedBundlePath : selectedBundleSummary,
            selectedBundleVerification,
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
            "Vital files directory: \(settings.vitalFilesDirectory)",
            "Restart services: \(settings.restartAfterSave ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
        ].joined(separator: "\n")
    }

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

    func uninstallRuntime(clean: Bool = false) async {
        let command: String
        if FileManager.default.isExecutableFile(atPath: runtime.uninstaller) {
            command = ([runtime.uninstaller] + (clean ? ["--clean"] : [])).map(shellQuote).joined(separator: " ")
        } else {
            message = AppConstants.StatusText.missingUninstaller
            return
        }

        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.uninstallPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.uninstallRunning,
            successMessage: clean
                ? AppConstants.StatusText.cleanUninstallCompleted
                : AppConstants.StatusText.uninstallCompleted
        )
        await refreshHealthStatus()
    }

    func saveSettingsDraft() {
        guard validateSettings() else {
            return
        }
        settings.saveDraft()
        message = AppConstants.StatusText.settingsDraftSaved
    }

    func prepareApplySettings() -> Bool {
        validateSettings()
    }

    func applySettings() async {
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        guard validateSettings() else {
            return
        }
        var adminPasswordFile: URL?
        if settings.changeAdminPassword {
            do {
                adminPasswordFile = try writeAdminPasswordFile(settings.adminPassword)
            } catch {
                message = error.localizedDescription
                return
            }
        }
        defer {
            if let adminPasswordFile {
                try? FileManager.default.removeItem(at: adminPasswordFile)
            }
        }
        let command = shellCommand(
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
            RuntimeSettings.clearDraft()
            settings.adminPassword = ""
            settings.changeAdminPassword = false
        }
        await refreshHealthStatus()
    }

    func chooseVitalFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppConstants.Actions.chooseDirectory
        if panel.runModal() == .OK, let url = panel.url {
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
            selectedBundleSummary = updateBundleSummary(url: url)
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
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = shellCommand(
            executable: runtime.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.applyBundle,
                selectedBundlePath,
            ]
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

    func verifySelectedBundle() async {
        guard !selectedBundlePath.isEmpty else {
            selectedBundleVerification = ""
            selectedBundleVerified = false
            message = AppConstants.StatusText.missingBundle
            return
        }
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            selectedBundleVerification = AppConstants.StatusText.missingLauncher
            selectedBundleVerified = false
            message = AppConstants.StatusText.missingLauncher
            return
        }

        isBusy = true
        defer { isBusy = false }

        message = AppConstants.StatusText.updateBundleVerifying
        let result = await ProcessRunner.run(
            runtime.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.verifyBundle,
                selectedBundlePath,
            ]
        )
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
        guard FileManager.default.isExecutableFile(atPath: runtime.launcher) else {
            message = AppConstants.StatusText.missingLauncher
            return
        }
        let command = shellCommand(
            executable: runtime.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.rollback,
            ] + (selectedBackupPath.isEmpty ? [] : [selectedBackupPath])
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

    func repairProxyPort() async {
        let proxyPort = status.proxyPort
        let command = proxyRepairCommand(proxyPort: proxyPort)
        _ = await runPrivileged(
            shellCommand: command,
            preparingMessage: AppConstants.StatusText.proxyRepairPreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.proxyRepairRunning,
            successMessage: AppConstants.StatusText.proxyRepairCompleted
        )
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

    private func validateSettings() -> Bool {
        if settings.networkMode == AppConstants.Values.networkBridged,
           settings.bridgedInterface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = AppConstants.StatusText.bridgedInterfaceRequired
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

    private func writeAdminPasswordFile(_ password: String) throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("tirosh-vitalserver-admin-password-\(UUID().uuidString)")
        guard let data = password.data(using: .utf8) else {
            throw RuntimeControllerError.invalidAdminPassword
        }
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw RuntimeControllerError.adminPasswordFileCreateFailed
        }
        return url
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
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

    private func proxyRepairCommand(proxyPort: Int) -> String {
        let script = """
        set -euo pipefail
        port=\(proxyPort)
        echo "Checking TCP port ${port}..."
        if [ ! -x \(shellQuote(AppConstants.Commands.lsof)) ]; then
          echo "lsof is not available"
          exit 1
        fi
        expected_nginx_pid=""
        if [ -s \(shellQuote(AppConstants.Paths.proxyNginxPid)) ]; then
          expected_nginx_pid="$(cat \(shellQuote(AppConstants.Paths.proxyNginxPid)) 2>/dev/null || true)"
        fi
        listeners="$(\(shellQuote(AppConstants.Commands.lsof)) -nP -iTCP:${port} -sTCP:LISTEN 2>/dev/null || true)"
        if [ -n "${listeners}" ]; then
          printf "%s\\n" "${listeners}"
        else
          echo "No listeners found on TCP port ${port}."
        fi
        nginx_pids="$(printf "%s\\n" "${listeners}" | awk 'NR>1 && $1 == "nginx" {print $2}' | sort -u | paste -sd" " -)"
        other_listeners="$(printf "%s\\n" "${listeners}" | awk 'NR>1 && $1 != "nginx" {print $1 "/" $2}' | sort -u | paste -sd, -)"
        foreign_nginx_pids="${nginx_pids}"
        if [ -n "${expected_nginx_pid}" ] && printf " %s " "${nginx_pids}" | grep -q " ${expected_nginx_pid} "; then
          echo "Configured host proxy nginx is already listening: ${nginx_pids}"
          foreign_nginx_pids=""
        fi
        if [ -n "${foreign_nginx_pids}" ]; then
          echo "Stopping foreign nginx listeners: ${foreign_nginx_pids}"
          kill -TERM ${foreign_nginx_pids} || true
          sleep 1
        fi
        if [ -n "${other_listeners}" ]; then
          echo "Non-nginx listeners remain on port ${port}: ${other_listeners}"
          echo "Stop that process or change the proxy port in Settings."
          exit 2
        fi
        echo "Restarting host proxy service..."
        \(shellQuote(AppConstants.Commands.launchctl)) kickstart -k system/\(AppConstants.Launchd.proxyService)
        sleep 2
        \(shellQuote(AppConstants.Commands.launchctl)) print system/\(AppConstants.Launchd.proxyService) >/dev/null
        echo "Host proxy service restarted."
        """
        return "/bin/bash -lc \(shellQuote(script))"
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

private enum RuntimeControllerError: LocalizedError {
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
