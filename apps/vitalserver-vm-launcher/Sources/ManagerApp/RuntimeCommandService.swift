import Foundation

@MainActor
protocol PrivilegedCommandRunning {
    func run(shellCommand: String) async -> ProcessResult
}

@MainActor
struct SystemPrivilegedCommandRunner: PrivilegedCommandRunning {
    func run(shellCommand: String) async -> ProcessResult {
        let loggedCommand = RuntimeCommandFactory.commandWithLog(shellCommand)
        let script = #"do shell script "\#(RuntimeCommandFactory.appleScriptEscaped(loggedCommand))" with administrator privileges"#
        return await ProcessRunner.run(AppConstants.Commands.osascript, arguments: ["-e", script])
    }
}

enum RuntimeCommandFactory {
    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        var parts: [String] = []
        if executable == AppConstants.Paths.launcher {
            parts.append(shellQuote(AppConstants.Commands.env))
            parts.append("\(AppConstants.Environment.vmHome)=\(shellQuote(AppConstants.Paths.vmHome))")
        }
        parts += ([executable] + arguments).map(shellQuote)
        return parts.joined(separator: " ")
    }

    static func uninstallCommand(uninstaller: String, clean: Bool) -> String {
        ([uninstaller] + (clean ? ["--clean"] : [])).map(shellQuote).joined(separator: " ")
    }

    static func deleteBackupCommand(url: URL) -> String {
        shellCommand(executable: AppConstants.Commands.rm, arguments: ["-rf", "--", url.path])
    }

    static func proxyRepairCommand(proxyPort: Int) -> String {
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

    static func runtimeServicesCommand(action: RuntimeServicesAction) -> String {
        shellCommand(
            executable: AppConstants.Paths.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                action.runtimeCommand,
            ]
        )
    }

    static func relaunchHelperCommand() -> String {
        [
            shellCommand(executable: AppConstants.Commands.sleep, arguments: ["1"]),
            shellCommand(executable: AppConstants.Commands.open, arguments: ["-n", AppConstants.Paths.managerApp]),
        ].joined(separator: " && ")
    }

    static func commandWithLog(_ shellCommand: String) -> String {
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

    static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum RuntimeServicesAction {
    case start
    case stop

    var runtimeCommand: String {
        switch self {
        case .start:
            return AppConstants.RuntimeCommand.startServices
        case .stop:
            return AppConstants.RuntimeCommand.stopServices
        }
    }
}
