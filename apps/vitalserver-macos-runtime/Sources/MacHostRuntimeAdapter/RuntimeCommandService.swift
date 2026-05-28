import Foundation
import RuntimeControl
import Core
import Contracts

protocol PrivilegedCommandRunning: Sendable {
    func run(shellCommand: String) async -> RuntimeCommandResult
}

struct SystemPrivilegedCommandRunner: PrivilegedCommandRunning {
    init() {}

    func run(shellCommand: String) async -> RuntimeCommandResult {
        let loggedCommand = RuntimeCommandFactory.commandWithLog(shellCommand)
        let script = #"do shell script "\#(RuntimeCommandFactory.appleScriptEscaped(loggedCommand))" with administrator privileges"#
        return await ProcessRunner.run(RuntimeAdapterConstants.Commands.osascript, arguments: ["-e", script])
    }
}

enum RuntimeCommandFactory {
    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        var parts: [String] = []
        if executable == RuntimeAdapterConstants.Paths.launcher {
            parts.append(shellQuote(RuntimeAdapterConstants.Commands.env))
            parts.append("\(RuntimeAdapterConstants.Environment.vmHome)=\(shellQuote(RuntimeAdapterConstants.Paths.vmHome))")
        }
        parts += ([executable] + arguments).map(shellQuote)
        return parts.joined(separator: " ")
    }

    static func uninstallCommand(uninstaller: String, clean: Bool) -> String {
        ([uninstaller] + (clean ? ["--clean"] : [])).map(shellQuote).joined(separator: " ")
    }

    static func deleteBackupCommand(url: URL) -> String {
        shellCommand(executable: RuntimeAdapterConstants.Commands.rm, arguments: ["-rf", "--", url.path])
    }

    static func configureRuntimeArguments(settings: RuntimeSettings, adminPasswordFile: String? = nil) -> [String] {
        var arguments = [
            RuntimeAdapterConstants.RuntimeCommand.runtime,
            RuntimeAdapterConstants.RuntimeCommand.configure,
            RuntimeAdapterConstants.RuntimeCommand.optionCPU,
            String(settings.cpuCount),
            RuntimeAdapterConstants.RuntimeCommand.optionMemoryGiB,
            String(settings.memoryGiB),
            RuntimeAdapterConstants.RuntimeCommand.optionDiskGiB,
            String(settings.diskGiB),
            RuntimeAdapterConstants.RuntimeCommand.optionNetwork,
            settings.networkMode.rawValue,
            RuntimeAdapterConstants.RuntimeCommand.optionProxyPort,
            String(settings.proxyPort),
            RuntimeAdapterConstants.RuntimeCommand.optionVitalFilesDirectory,
            settings.vitalFilesDirectory,
            RuntimeAdapterConstants.RuntimeCommand.optionPublicHost,
            settings.publicHost,
            RuntimeAdapterConstants.RuntimeCommand.optionPublicPort,
            String(settings.publicPort),
            RuntimeAdapterConstants.RuntimeCommand.optionRedisBackupRetention,
            String(settings.redisBackupRetentionCount),
        ]
        if settings.startOnBootConfigurable {
            arguments += [
                RuntimeAdapterConstants.RuntimeCommand.optionStartOnBoot,
                settings.startOnBoot
                    ? RuntimeAdapterConstants.RuntimeCommand.boolTrue
                    : RuntimeAdapterConstants.RuntimeCommand.boolFalse,
            ]
        }
        arguments += [
            RuntimeAdapterConstants.RuntimeCommand.optionAutoRecovery,
            settings.autoRecoveryEnabled
                ? RuntimeAdapterConstants.RuntimeCommand.boolTrue
                : RuntimeAdapterConstants.RuntimeCommand.boolFalse,
            RuntimeAdapterConstants.RuntimeCommand.optionPreventSystemSleep,
            settings.preventSystemSleep
                ? RuntimeAdapterConstants.RuntimeCommand.boolTrue
                : RuntimeAdapterConstants.RuntimeCommand.boolFalse,
        ]
        if settings.networkMode == .bridged, !settings.bridgedInterface.isEmpty {
            arguments += [RuntimeAdapterConstants.RuntimeCommand.optionBridgedInterface, settings.bridgedInterface]
        }
        if let adminPasswordFile {
            arguments += [RuntimeAdapterConstants.RuntimeCommand.optionAdminPasswordFile, adminPasswordFile]
        }
        if settings.restartAfterSave {
            arguments.append(RuntimeAdapterConstants.RuntimeCommand.optionRestart)
        }
        return arguments
    }

    static func proxyRepairCommand(proxyPort: Int) -> String {
        let script = """
        set -euo pipefail
        port=\(proxyPort)
        echo "Checking TCP port ${port}..."
        if [ ! -x \(shellQuote(RuntimeAdapterConstants.Commands.lsof)) ]; then
          echo "lsof is not available"
          exit 1
        fi
        expected_nginx_pid=""
        if [ -s \(shellQuote(RuntimeAdapterConstants.Paths.proxyNginxPid)) ]; then
          expected_nginx_pid="$(cat \(shellQuote(RuntimeAdapterConstants.Paths.proxyNginxPid)) 2>/dev/null || true)"
        fi
        listeners="$(\(shellQuote(RuntimeAdapterConstants.Commands.lsof)) -nP -iTCP:${port} -sTCP:LISTEN 2>/dev/null || true)"
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
        \(shellQuote(RuntimeAdapterConstants.Commands.launchctl)) kickstart -k system/\(RuntimeManagedService.proxy.label)
        sleep 2
        \(shellQuote(RuntimeAdapterConstants.Commands.launchctl)) print system/\(RuntimeManagedService.proxy.label) >/dev/null
        echo "Host proxy service restarted."
        """
        return "/bin/bash -lc \(shellQuote(script))"
    }

    static func runtimeServicesCommand(action: RuntimeServicesAction) -> String {
        shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                action.runtimeCommand,
            ]
        )
    }

    static func commandWithLog(_ shellCommand: String) -> String {
        let logFile = shellQuote(RuntimeAdapterConstants.Paths.commandLogFile)
        let script = [
            "rm -f \(logFile)",
            "{ \(shellCommand); } > \(logFile) 2>&1",
            "status=$?",
            "tail -n 200 \(logFile)",
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
    case repair
    case start
    case stop

    var runtimeCommand: String {
        switch self {
        case .start:
            return RuntimeAdapterConstants.RuntimeCommand.startServices
        case .stop:
            return RuntimeAdapterConstants.RuntimeCommand.stopServices
        case .repair:
            return RuntimeAdapterConstants.RuntimeCommand.repairServices
        }
    }
}
