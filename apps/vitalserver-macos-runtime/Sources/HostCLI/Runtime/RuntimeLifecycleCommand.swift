import Foundation
import Core
import Contracts

enum RuntimeLifecycleCommand: Equatable {
    case install
    case status
    case health
    case watchdog
    case configure(RuntimeConfigureCommand)
    case verifyBundle(URL)
    case stageBundle(URL)
    case applyBundle(URL)
    case rollback(RuntimeRollbackCommand)
    case repairDatastore
    case startServices
    case stopServices
    case help

    static func parse(_ arguments: [String]) throws -> RuntimeLifecycleCommand {
        guard let command = arguments.first else {
            return .help
        }

        let remaining = Array(arguments.dropFirst())
        switch command {
        case "install":
            return .install
        case "status":
            return .status
        case "health":
            return .health
        case "watchdog":
            return .watchdog
        case "configure":
            return .configure(try parseConfigureCommand(remaining))
        case "verify-bundle":
            return .verifyBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime verify-bundle <bundle.tar.gz>"
            ))
        case "stage-bundle":
            return .stageBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime stage-bundle <bundle.tar.gz>"
            ))
        case "apply-bundle":
            return .applyBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime apply-bundle <bundle.tar.gz>"
            ))
        case "rollback":
            return .rollback(parseRollbackCommand(remaining))
        case "repair-datastore":
            return .repairDatastore
        case "start-services":
            return .startServices
        case "stop-services":
            return .stopServices
        case "-h", "--help", "help":
            return .help
        default:
            throw LauncherError.unsupportedCommand("runtime \(command)")
        }
    }

    static let usage = """
    Usage:
      vitalserver-vm runtime install
      vitalserver-vm runtime status
      vitalserver-vm runtime health
      vitalserver-vm runtime watchdog
      vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--disk-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--vital-files-dir <path>] [--public-host <host>] [--public-port <port>] [--admin-password <password>] [--start-on-boot true|false] [--restart]
      vitalserver-vm runtime configure [--admin-password-file <path>] [--restart]
      vitalserver-vm runtime verify-bundle <bundle.tar.gz>
      vitalserver-vm runtime stage-bundle <bundle.tar.gz>
      vitalserver-vm runtime apply-bundle <bundle.tar.gz>
      vitalserver-vm runtime rollback [backup-dir]
      vitalserver-vm runtime repair-datastore
      vitalserver-vm runtime start-services
      vitalserver-vm runtime stop-services
    """

    private static func requiredBundleURL(in arguments: [String], usage: String) throws -> URL {
        guard let bundlePath = arguments.first else {
            throw LauncherError.missingArgument(usage)
        }
        return URL(fileURLWithPath: bundlePath)
    }

    private static func parseRollbackCommand(_ arguments: [String]) -> RuntimeRollbackCommand {
        guard let backupPath = arguments.first else {
            return .latestBackup
        }
        return .specificBackup(URL(fileURLWithPath: backupPath))
    }

    private static func parseConfigureCommand(_ arguments: [String]) throws -> RuntimeConfigureCommand {
        var remaining = arguments
        var changes: [RuntimeConfigureChange] = []
        var restart = false

        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            let option = RuntimeConfigureOption(rawValue: key)
            if option == .restart {
                restart = true
                continue
            }

            guard option.requiresValue else {
                continue
            }
            guard let value = remaining.first else {
                throw LauncherError.missingArgument("missing value for \(key)")
            }
            remaining.removeFirst()
            changes.append(try configureChange(option: option, value: value))
        }

        return RuntimeConfigureCommand(changes: changes, restart: restart)
    }

    private static func configureChange(option: RuntimeConfigureOption, value: String) throws -> RuntimeConfigureChange {
        switch option {
        case .cpu:
            guard let cpu = Int(value) else {
                throw LauncherError.missingArgument("--cpu must be an integer")
            }
            return .cpu(cpu)
        case .memoryGiB:
            guard let memoryGiB = UInt64(value) else {
                throw LauncherError.missingArgument("--memory-gib must be an integer")
            }
            return .memoryGiB(memoryGiB)
        case .diskGiB:
            guard let diskGiB = Int(value) else {
                throw LauncherError.missingArgument("--disk-gib must be an integer")
            }
            return .diskGiB(diskGiB)
        case .network:
            guard let mode = NetworkMode(rawValue: value) else {
                throw LauncherError.missingArgument("--network must be `shared` or `bridged`")
            }
            return .network(mode)
        case .bridgedInterface:
            return .bridgedInterface(value)
        case .proxyPort:
            guard let port = Int(value) else {
                throw LauncherError.missingArgument("--proxy-port must be an integer")
            }
            return .proxyPort(port)
        case .vitalFilesDirectory:
            guard value.hasPrefix("/") else {
                throw LauncherError.missingArgument("--vital-files-dir must be an absolute path")
            }
            return .vitalFilesDirectory(URL(fileURLWithPath: value))
        case .publicHost:
            return .publicHost(value)
        case .publicPort:
            guard let port = Int(value) else {
                throw LauncherError.missingArgument("--public-port must be an integer")
            }
            return .publicPort(port)
        case .adminPassword:
            return .adminPassword(value)
        case .adminPasswordFile:
            return .adminPasswordFile(URL(fileURLWithPath: value))
        case .startOnBoot:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw LauncherError.missingArgument("--start-on-boot must be true or false")
            }
            return .startOnBoot(enabled)
        case .autoRecovery:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw LauncherError.missingArgument("--auto-recovery must be true or false")
            }
            return .autoRecovery(enabled)
        case .restart:
            throw LauncherError.missingArgument("--restart does not accept a value")
        case .unknown(let key):
            throw LauncherError.missingArgument("unsupported runtime configure option: \(key)")
        }
    }
}
