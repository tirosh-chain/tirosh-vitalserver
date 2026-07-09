import Foundation

enum RuntimeUninstallCommandFactory {
    static func uninstallCommand(uninstaller: String, clean: Bool, forceClean: Bool = false) -> String {
        let shellQuote = RuntimeShellCommandFactory.shellQuote
        let uninstallArguments: [String]
        if forceClean {
            uninstallArguments = ["--force-clean-uninstaller"]
        } else if clean {
            uninstallArguments = ["--clean"]
        } else {
            uninstallArguments = []
        }
        let command = ([uninstaller] + uninstallArguments).map(shellQuote).joined(separator: " ")
        let logPath = InstalledRuntimePaths.defaultInstalled.runtimeUninstallLog.path
        let previousLogPath = "\(logPath).previous"
        let viewerScriptPath = "/private/tmp/tirosh-vitalserver-uninstall-progress.command"
        let startScript = RuntimeUninstallProgressScript.startScript(
            plan: RuntimeUninstallProgressScriptPlan(
                command: command,
                logPath: logPath,
                previousLogPath: previousLogPath,
                viewerScriptPath: viewerScriptPath
            ),
            shellQuote: shellQuote
        )
        let script = [
            "mkdir -p \(shellQuote((logPath as NSString).deletingLastPathComponent))",
            startScript
        ].joined(separator: "; ")
        return "/bin/bash -lc \(shellQuote(script))"
    }
}
