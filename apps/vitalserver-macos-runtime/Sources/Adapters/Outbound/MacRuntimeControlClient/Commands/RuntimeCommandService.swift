import Foundation
import RuntimeControl
import Application
import Contracts
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
        RuntimeShellCommandFactory.shellQuote(value)
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        RuntimeShellCommandFactory.shellCommand(executable: executable, arguments: arguments)
    }

    static func uninstallCommand(uninstaller: String, clean: Bool, forceClean: Bool = false) -> String {
        RuntimeUninstallCommandFactory.uninstallCommand(
            uninstaller: uninstaller,
            clean: clean,
            forceClean: forceClean
        )
    }

    static func deleteBackupCommand(url: URL) -> String {
        shellCommand(executable: RuntimeControlClientConstants.Commands.rm, arguments: ["-rf", "--", url.path])
    }

    static func configureRuntimeArguments(
        settings: RuntimeSettings,
        adminPasswordFile: String? = nil,
        redisRelaySettingsFile: String? = nil
    ) -> [String] {
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
            RuntimeControlClientConstants.RuntimeCommand.optionAutomaticBackup,
            settings.automaticBackupEnabled
                ? RuntimeControlClientConstants.RuntimeCommand.boolTrue
                : RuntimeControlClientConstants.RuntimeCommand.boolFalse,
            RuntimeControlClientConstants.RuntimeCommand.optionBackupScheduleTimes,
            settings.backupScheduleTimes.joined(separator: ","),
            RuntimeControlClientConstants.RuntimeCommand.optionBackupRetention,
            String(settings.backupRetentionCount),
            RuntimeControlClientConstants.RuntimeCommand.optionLogArchiveRetentionDays,
            String(settings.logArchiveRetentionDays),
            RuntimeControlClientConstants.RuntimeCommand.optionLogArchiveMaximumGiB,
            String(settings.logArchiveMaximumGiB),
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
        if settings.networkMode == .bridged,
           let bridgedInterface = settings.bridgedInterface,
           !bridgedInterface.isEmpty {
            arguments += [RuntimeControlClientConstants.RuntimeCommand.optionBridgedInterface, bridgedInterface]
        }
        if let adminPasswordFile {
            arguments += [RuntimeControlClientConstants.RuntimeCommand.optionAdminPasswordFile, adminPasswordFile]
        }
        if let redisRelaySettingsFile {
            arguments += [
                RuntimeControlClientConstants.RuntimeCommand.optionRedisRelaySettingsFile,
                redisRelaySettingsFile,
            ]
        }
        if settings.restartAfterSave {
            arguments.append(RuntimeControlClientConstants.RuntimeCommand.optionRestart)
        }
        return arguments
    }

    static func proxyRepairCommand() -> String {
        shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.repairProxy,
            ]
        )
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
        RuntimeShellCommandFactory.commandWithLog(shellCommand)
    }

    static func appleScriptEscaped(_ value: String) -> String {
        RuntimeShellCommandFactory.appleScriptEscaped(value)
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
