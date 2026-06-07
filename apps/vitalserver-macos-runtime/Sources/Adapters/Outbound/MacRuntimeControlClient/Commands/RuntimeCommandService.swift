import Foundation
import RuntimeControl
import Application
import Contracts
import Domain
import Errors

protocol PrivilegedCommandRunning: Sendable {
    func run(shellCommand: String) async -> RuntimeCommandResult
}

struct SystemPrivilegedCommandRunner: PrivilegedCommandRunning {
    init() {}

    func run(shellCommand: String) async -> RuntimeCommandResult {
        let loggedCommand = RuntimeCommandFactory.commandWithLog(shellCommand)
        let script = #"do shell script "\#(RuntimeCommandFactory.appleScriptEscaped(loggedCommand))" with administrator privileges"#
        return await ProcessRunner.run(RuntimeControlClientConstants.Commands.osascript, arguments: ["-e", script])
    }
}

enum RuntimeCommandFactory {
    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        var parts: [String] = []
        if executable == RuntimeControlClientConstants.Paths.launcher {
            parts.append(shellQuote(RuntimeControlClientConstants.Commands.env))
            parts.append("\(RuntimeControlClientConstants.Environment.vmHome)=\(shellQuote(RuntimeControlClientConstants.Paths.vmHome))")
        }
        parts += ([executable] + arguments).map(shellQuote)
        return parts.joined(separator: " ")
    }

    static func uninstallCommand(uninstaller: String, clean: Bool) -> String {
        let command = ([uninstaller] + (clean ? ["--clean"] : [])).map(shellQuote).joined(separator: " ")
        let logPath = RuntimeControlClientConstants.Paths.uninstallLog
        let previousLogPath = "\(logPath).previous"
        let viewerScriptPath = "/private/tmp/tirosh-vitalserver-uninstall-progress.command"
        let viewerScript = """
        #!/usr/bin/env bash
        set -u
        log_file=\(shellQuote(logPath))
        printf "VitalServer uninstall progress\\n"
        printf "Log: %s\\n\\n" "${log_file}"
        touch "${log_file}" 2>/dev/null || true
        tail -n 0 -F "${log_file}" &
        tail_pid=$!
        while true; do
          if grep -q "uninstall completed log=" "${log_file}" 2>/dev/null; then
            kill "${tail_pid}" 2>/dev/null || true
            wait "${tail_pid}" 2>/dev/null || true
            printf "\\nUninstall completed.\\n"
            break
          fi
          if grep -q "uninstall failed" "${log_file}" 2>/dev/null; then
            kill "${tail_pid}" 2>/dev/null || true
            wait "${tail_pid}" 2>/dev/null || true
            printf "\\nUninstall failed. Check the log above.\\n"
            break
          fi
          sleep 1
        done
        printf "Press Return to close this window."
        read -r _
        """
        let startScript = """
        log_file=\(shellQuote(logPath))
        previous_log_file=\(shellQuote(previousLogPath))
        viewer_script=\(shellQuote(viewerScriptPath))
        if [ -s "${log_file}" ]; then
          cp "${log_file}" "${previous_log_file}"
        fi
        : > "${log_file}"
        printf %s \(shellQuote(viewerScript)) > "${viewer_script}"
        chmod 0755 "${viewer_script}"
        open -a Terminal "${viewer_script}" >/dev/null 2>&1 || true
        \(command) < /dev/null >> "${log_file}" 2>&1 &
        background_pid=$!
        sleep 0.2
        if kill -0 "${background_pid}" 2>/dev/null; then
          echo "Background uninstaller started."
        else
          wait "${background_pid}"
        fi
        """
        let script = [
            "mkdir -p \(shellQuote((RuntimeControlClientConstants.Paths.uninstallLog as NSString).deletingLastPathComponent))",
            startScript
        ].joined(separator: "; ")
        return "/bin/bash -lc \(shellQuote(script))"
    }

    static func deleteBackupCommand(url: URL) -> String {
        shellCommand(executable: RuntimeControlClientConstants.Commands.rm, arguments: ["-rf", "--", url.path])
    }

    static func configureRuntimeArguments(settings: RuntimeSettings, adminPasswordFile: String? = nil) -> [String] {
        var arguments = [
            RuntimeControlClientConstants.RuntimeCommand.runtime,
            RuntimeControlClientConstants.RuntimeCommand.configure,
            RuntimeControlClientConstants.RuntimeCommand.optionCPU,
            String(settings.cpuCount),
            RuntimeControlClientConstants.RuntimeCommand.optionMemoryGiB,
            String(settings.memoryGiB),
            RuntimeControlClientConstants.RuntimeCommand.optionDiskGiB,
            String(settings.diskGiB),
            RuntimeControlClientConstants.RuntimeCommand.optionNetwork,
            settings.networkMode.rawValue,
            RuntimeControlClientConstants.RuntimeCommand.optionProxyPort,
            String(settings.proxyPort),
            RuntimeControlClientConstants.RuntimeCommand.optionVitalFilesDirectory,
            settings.vitalFilesDirectory,
            RuntimeControlClientConstants.RuntimeCommand.optionPublicHost,
            settings.publicHost,
            RuntimeControlClientConstants.RuntimeCommand.optionPublicPort,
            String(settings.publicPort),
            RuntimeControlClientConstants.RuntimeCommand.optionVitalServerURL,
            settings.vitalServerURL,
            RuntimeControlClientConstants.RuntimeCommand.optionRemoteConsoleURL,
            settings.remoteConsoleURL,
            RuntimeControlClientConstants.RuntimeCommand.optionRedisBackupRetention,
            String(settings.redisBackupRetentionCount),
        ]
        if settings.startOnBootConfigurable {
            arguments += [
                RuntimeControlClientConstants.RuntimeCommand.optionStartOnBoot,
                settings.startOnBoot
                    ? RuntimeControlClientConstants.RuntimeCommand.boolTrue
                    : RuntimeControlClientConstants.RuntimeCommand.boolFalse,
            ]
        }
        arguments += [
            RuntimeControlClientConstants.RuntimeCommand.optionAutoRecovery,
            settings.autoRecoveryEnabled
                ? RuntimeControlClientConstants.RuntimeCommand.boolTrue
                : RuntimeControlClientConstants.RuntimeCommand.boolFalse,
            RuntimeControlClientConstants.RuntimeCommand.optionPreventSystemSleep,
            settings.preventSystemSleep
                ? RuntimeControlClientConstants.RuntimeCommand.boolTrue
                : RuntimeControlClientConstants.RuntimeCommand.boolFalse,
        ]
        if settings.networkMode == .bridged, !settings.bridgedInterface.isEmpty {
            arguments += [RuntimeControlClientConstants.RuntimeCommand.optionBridgedInterface, settings.bridgedInterface]
        }
        if let adminPasswordFile {
            arguments += [RuntimeControlClientConstants.RuntimeCommand.optionAdminPasswordFile, adminPasswordFile]
        }
        if settings.restartAfterSave {
            arguments.append(RuntimeControlClientConstants.RuntimeCommand.optionRestart)
        }
        return arguments
    }

    static func proxyRepairCommand(proxyPort: Int) -> String {
        let script = """
        set -euo pipefail
        port=\(proxyPort)
        echo "Checking TCP port ${port}..."
        if [ ! -x \(shellQuote(RuntimeControlClientConstants.Commands.lsof)) ]; then
          echo "lsof is not available"
          exit 1
        fi
        expected_nginx_pid=""
        if [ -s \(shellQuote(RuntimeControlClientConstants.Paths.proxyNginxPid)) ]; then
          expected_nginx_pid="$(cat \(shellQuote(RuntimeControlClientConstants.Paths.proxyNginxPid)) 2>/dev/null || true)"
        fi
        listeners="$(\(shellQuote(RuntimeControlClientConstants.Commands.lsof)) -nP -iTCP:${port} -sTCP:LISTEN 2>/dev/null || true)"
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
        \(shellQuote(RuntimeControlClientConstants.Commands.launchctl)) kickstart -k system/\(RuntimeManagedService.proxy.label)
        sleep 2
        \(shellQuote(RuntimeControlClientConstants.Commands.launchctl)) print system/\(RuntimeManagedService.proxy.label) >/dev/null
        echo "Host proxy service restarted."
        """
        return "/bin/bash -lc \(shellQuote(script))"
    }

    static func runtimeServicesCommand(action: RuntimeServicesAction) -> String {
        shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                action.runtimeCommand,
            ]
        )
    }

    static func commandWithLog(_ shellCommand: String) -> String {
        let logFile = shellQuote(RuntimeControlClientConstants.Paths.commandLogFile)
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
            return RuntimeControlClientConstants.RuntimeCommand.startServices
        case .stop:
            return RuntimeControlClientConstants.RuntimeCommand.stopServices
        case .repair:
            return RuntimeControlClientConstants.RuntimeCommand.repairServices
        }
    }
}
