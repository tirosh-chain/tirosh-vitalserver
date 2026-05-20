import AppKit
import Foundation

@MainActor
final class RuntimeController: ObservableObject {
    @Published var status = RuntimeStatus()
    @Published var message = AppConstants.StatusText.ready
    @Published var isBusy = false

    private let runtime = RuntimePaths()

    func refresh() async {
        status = RuntimeStatus.load(paths: runtime)
    }

    func refreshHealthStatus() async {
        status = await loadHealthStatus()
    }

    func healthCheck() async {
        isBusy = true
        defer { isBusy = false }

        status = await loadHealthStatus()
        message = AppConstants.StatusText.healthCheckCompleted
    }

    func installRuntime(settings: InstallSettings) async {
        let currentStatus = RuntimeStatus.load(paths: runtime)
        if currentStatus.runtimeInstalled {
            status = currentStatus
            message = AppConstants.StatusText.installAlreadyPresent
            return
        }

        guard let pkgURL = Bundle.main.url(
            forResource: AppConstants.Product.bundledPackageName,
            withExtension: AppConstants.Product.bundledPackageExtension
        ) else {
            message = AppConstants.StatusText.missingBundledPackage
            return
        }

        message = [
            AppConstants.StatusText.installSettingsCaptured,
            settings.summaryLines.joined(separator: "\n")
        ].joined(separator: "\n\n")

        do {
            try settings.installEnvironment.write(
                toFile: AppConstants.Paths.installSettingsFile,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            message = "\(AppConstants.StatusText.installSettingsWriteFailed)\n\(error.localizedDescription)"
            return
        }

        let installed = await runPrivileged(
            shellCommand: "\(AppConstants.Commands.installer) -pkg \(shellQuote(pkgURL.path)) -target /",
            preparingMessage: AppConstants.StatusText.installPreparing,
            waitingMessage: AppConstants.StatusText.installWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.installRunning,
            successMessage: AppConstants.StatusText.installCompleted
        )
        if installed {
            await waitForRuntimeReadiness()
        } else {
            await refreshHealthStatus()
        }
    }

    func uninstallRuntime() async {
        let command: String
        if FileManager.default.isExecutableFile(atPath: runtime.uninstaller) {
            command = shellQuote(runtime.uninstaller)
        } else if let bundled = Bundle.main.url(
            forResource: AppConstants.Product.bundledUninstallerName,
            withExtension: nil
        ) {
            command = shellQuote(bundled.path)
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

    func openVitalServer() {
        NSWorkspace.shared.open(URL(string: AppConstants.Product.vitalServerURL)!)
    }

    func openRedisUI() {
        NSWorkspace.shared.open(URL(string: AppConstants.Product.redisUIURL)!)
    }

    func openSwagger() {
        NSWorkspace.shared.open(URL(string: AppConstants.Product.swaggerURL)!)
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

    private func waitForRuntimeReadiness() async {
        isBusy = true
        defer { isBusy = false }

        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            let next = await loadHealthStatus()
            status = next

            message = readinessMessage(for: next)
            if next.isReady {
                message = [
                    AppConstants.StatusText.installReady,
                    readinessSummary(for: next)
                ].joined(separator: "\n\n")
                return
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        status = await loadHealthStatus()
        message = [
            AppConstants.StatusText.installReadinessTimedOut,
            readinessSummary(for: status)
        ].joined(separator: "\n\n")
    }

    private func loadHealthStatus() async -> RuntimeStatus {
        var next = RuntimeStatus.load(paths: runtime)

        if let vmIP = next.vmIP {
            next.guestHTTP = await httpStatus(url: AppConstants.Product.guestHealthURL(vmIP: vmIP))
        }
        next.hostProxyHTTP = await httpStatus(url: AppConstants.Product.hostProxyHealthURL)

        return next
    }

    private func readinessMessage(for status: RuntimeStatus) -> String {
        [
            AppConstants.StatusText.installWaitingForRuntime,
            readinessSummary(for: status)
        ].joined(separator: "\n\n")
    }

    private func readinessSummary(for status: RuntimeStatus) -> String {
        [
            "Runtime: \(status.runtimeInstalled ? AppConstants.StatusText.installed : AppConstants.StatusText.notInstalled)",
            "VM service: \(status.vmServiceLoaded ? AppConstants.StatusText.loaded : AppConstants.StatusText.notLoaded)",
            "Proxy service: \(status.proxyServiceLoaded ? AppConstants.StatusText.loaded : AppConstants.StatusText.notLoaded)",
            "VM IP: \(status.vmIP ?? AppConstants.StatusText.waiting)",
            "Guest HTTP: \(status.guestHTTP ?? AppConstants.StatusText.notChecked)",
            "Host proxy: \(status.hostProxyHTTP ?? AppConstants.StatusText.notChecked)"
        ].joined(separator: "\n")
    }

    private func httpStatus(url: String) async -> String {
        let result = await ProcessRunner.run(
            AppConstants.Commands.curl,
            arguments: ["-sS", "-I", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 ? code : AppConstants.StatusText.failed
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
