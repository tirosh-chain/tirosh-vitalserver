import Application
import Contracts
import Foundation
import Errors

public enum RuntimeLifecycleCommand: Equatable {
    case install
    case installProvision
    case preinstallCheck
    case status
    case health
    case guestLogSync
    case watchdog
    case configure(RuntimeConfigureCommand)
    case verifyBundle(URL)
    case stageBundle(URL)
    case applyBundle(URL)
    case rollback(RuntimeRollbackCommand)
    case redisBackup
    case redisRestore(URL)
    case runtimeDataBackup
    case automaticBackup
    case runtimeDataRestore(URL)
    case repairDatastore
    case repairVMDisk
    case repairProxy
    case repairServices
    case startServices
    case stopServices
    case uninstall(RuntimeUninstallCommand)
    case help
}

extension RuntimeLifecycleCommand {
    public static func parseArguments(_ arguments: [String]) throws -> RuntimeLifecycleCommand {
        guard let command = arguments.first else {
            return .help
        }

        let remaining = Array(arguments.dropFirst())
        switch command {
        case "install":
            return .install
        case "install-provision":
            return .installProvision
        case "preinstall-check":
            return .preinstallCheck
        case "status":
            return .status
        case "health":
            return .health
        case "guest-log-sync":
            return .guestLogSync
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
        case "redis-backup":
            return .redisBackup
        case "redis-restore":
            return .redisRestore(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime redis-restore <archive.tar.gz>"
            ))
        case "runtime-data-backup":
            return .runtimeDataBackup
        case "automatic-backup":
            return .automaticBackup
        case "runtime-data-restore":
            return .runtimeDataRestore(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime runtime-data-restore <backup-dir>"
            ))
        case "repair-datastore":
            return .repairDatastore
        case "repair-vm-disk":
            return .repairVMDisk
        case "repair-proxy":
            return .repairProxy
        case "repair-services":
            return .repairServices
        case "start-services":
            return .startServices
        case "stop-services":
            return .stopServices
        case "uninstall":
            return .uninstall(try parseUninstallCommand(remaining))
        case "-h", "--help", "help":
            return .help
        default:
            throw RuntimeLifecycleCommandParseError.unsupportedCommand("runtime \(command)")
        }
    }

    public static let usageText = """
    Usage:
      vitalserver-vm runtime install
      vitalserver-vm runtime install-provision
      vitalserver-vm runtime preinstall-check
      vitalserver-vm runtime status
      vitalserver-vm runtime health
      vitalserver-vm runtime guest-log-sync
      vitalserver-vm runtime watchdog
      vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--disk-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--vital-files-dir <path>] [--vitalserver-url <url>] [--remote-console-url <url>] [--public-host <host>] [--public-port <port>] [--admin-password <password>] [--start-on-boot true|false] [--auto-recovery true|false] [--prevent-system-sleep true|false] [--automatic-backup true|false] [--backup-schedule-times HH:mm[,HH:mm]] [--backup-retention <count>] [--log-archive-retention-days <days>] [--log-archive-maximum-gib <gib>] [--redis-relay-settings-file <path>] [--restart]
      vitalserver-vm runtime configure [--admin-password-file <path>] [--restart]
      vitalserver-vm runtime verify-bundle <bundle.tar.gz>
      vitalserver-vm runtime stage-bundle <bundle.tar.gz>
      vitalserver-vm runtime apply-bundle <bundle.tar.gz>
      vitalserver-vm runtime rollback [backup-dir]
      vitalserver-vm runtime redis-backup
      vitalserver-vm runtime redis-restore <archive.tar.gz>
      vitalserver-vm runtime runtime-data-backup
      vitalserver-vm runtime automatic-backup
      vitalserver-vm runtime runtime-data-restore <backup-dir>
      vitalserver-vm runtime repair-datastore
      vitalserver-vm runtime repair-vm-disk
      vitalserver-vm runtime repair-proxy
      vitalserver-vm runtime repair-services
      vitalserver-vm runtime start-services
      vitalserver-vm runtime stop-services
      vitalserver-vm runtime uninstall [--clean|--force-clean|--force-clean-uninstaller]
    """

    private static func requiredBundleURL(in arguments: [String], usage: String) throws -> URL {
        guard let bundlePath = arguments.first else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return URL(fileURLWithPath: bundlePath)
    }

    private static func parseRollbackCommand(_ arguments: [String]) -> RuntimeRollbackCommand {
        guard let backupPath = arguments.first else {
            return .latestBackup
        }
        return .specificBackup(URL(fileURLWithPath: backupPath))
    }

    private static func parseUninstallCommand(_ arguments: [String]) throws -> RuntimeUninstallCommand {
        var clean = false
        var forceClean = false
        for argument in arguments {
            switch argument {
            case "--clean":
                clean = true
            case "--force-clean":
                forceClean = true
                clean = true
            case "--force-clean-uninstaller":
                forceClean = true
                clean = true
            default:
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "usage: vitalserver-vm runtime uninstall [--clean|--force-clean|--force-clean-uninstaller]"
                )
            }
        }
        return RuntimeUninstallCommand(clean: clean, forceClean: forceClean)
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
                throw RuntimeLifecycleCommandParseError.missingArgument("missing value for \(key)")
            }
            remaining.removeFirst()
            changes.append(try configureChange(option: option, value: value))
        }

        return RuntimeConfigureCommand(changes: changes, restart: restart)
    }

    private static func configureChange(
        option: RuntimeConfigureOption,
        value: String
    ) throws -> RuntimeConfigureChange {
        switch option {
        case .cpu:
            guard let cpu = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--cpu must be an integer")
            }
            return .cpu(cpu)
        case .memoryGiB:
            guard let memoryGiB = UInt64(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--memory-gib must be an integer")
            }
            return .memoryGiB(memoryGiB)
        case .diskGiB:
            guard let diskGiB = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--disk-gib must be an integer")
            }
            return .diskGiB(diskGiB)
        case .network:
            guard let mode = RuntimeNetworkMode(rawValue: value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--network must be `shared` or `bridged`")
            }
            return .network(mode)
        case .bridgedInterface:
            return .bridgedInterface(value)
        case .proxyPort:
            guard let port = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--proxy-port must be an integer")
            }
            return .proxyPort(port)
        case .vitalFilesDirectory:
            guard value.hasPrefix("/") else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--vital-files-dir must be an absolute path"
                )
            }
            return .vitalFilesDirectory(URL(fileURLWithPath: value))
        case .vitalServerURL:
            return .vitalServerURL(value)
        case .remoteConsoleURL:
            return .remoteConsoleURL(value)
        case .publicHost:
            return .publicHost(value)
        case .publicPort:
            guard let port = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--public-port must be an integer")
            }
            return .publicPort(port)
        case .adminPassword:
            return .adminPassword(value)
        case .adminPasswordFile:
            return .adminPasswordFile(URL(fileURLWithPath: value))
        case .startOnBoot:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--start-on-boot must be true or false")
            }
            return .startOnBoot(enabled)
        case .autoRecovery:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--auto-recovery must be true or false")
            }
            return .autoRecovery(enabled)
        case .preventSystemSleep:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--prevent-system-sleep must be true or false"
                )
            }
            return .preventSystemSleep(enabled)
        case .automaticBackup:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--automatic-backup must be true or false")
            }
            return .automaticBackup(enabled)
        case .backupScheduleTimes:
            let times = value
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0) }
            return .backupScheduleTimes(times)
        case .backupRetention:
            guard let count = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--backup-retention must be an integer"
                )
            }
            return .backupRetention(count)
        case .logArchiveRetentionDays:
            guard let days = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--log-archive-retention-days must be an integer"
                )
            }
            return .logArchiveRetentionDays(days)
        case .logArchiveMaximumGiB:
            guard let gib = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--log-archive-maximum-gib must be an integer"
                )
            }
            return .logArchiveMaximumGiB(gib)
        case .redisRelaySettingsFile:
            guard value.hasPrefix("/") else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--redis-relay-settings-file must be an absolute path"
                )
            }
            return .redisRelaySettingsFile(URL(fileURLWithPath: value))
        case .restart:
            throw RuntimeLifecycleCommandParseError.missingArgument("--restart does not accept a value")
        case .unknown(let key):
            throw RuntimeLifecycleCommandParseError.missingArgument("unsupported runtime configure option: \(key)")
        }
    }
}
