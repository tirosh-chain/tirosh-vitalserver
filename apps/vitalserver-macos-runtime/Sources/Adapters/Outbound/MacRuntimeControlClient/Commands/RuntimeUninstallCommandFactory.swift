import Foundation

enum RuntimeUninstallCommandFactory {
    static func uninstallCommand(uninstaller: String, clean: Bool) -> String {
        let shellQuote = RuntimeShellCommandFactory.shellQuote
        let command = ([uninstaller] + (clean ? ["--clean"] : [])).map(shellQuote).joined(separator: " ")
        let logPath = RuntimeControlClientConstants.Paths.uninstallLog
        let previousLogPath = "\(logPath).previous"
        let viewerScriptPath = "/private/tmp/tirosh-vitalserver-uninstall-progress.command"
        let startScript = RuntimeUninstallProgressScript.startScript(
            command: command,
            logPath: logPath,
            previousLogPath: previousLogPath,
            viewerScriptPath: viewerScriptPath,
            shellQuote: shellQuote
        )
        let script = [
            "mkdir -p \(shellQuote((RuntimeControlClientConstants.Paths.uninstallLog as NSString).deletingLastPathComponent))",
            startScript
        ].joined(separator: "; ")
        return "/bin/bash -lc \(shellQuote(script))"
    }
}
