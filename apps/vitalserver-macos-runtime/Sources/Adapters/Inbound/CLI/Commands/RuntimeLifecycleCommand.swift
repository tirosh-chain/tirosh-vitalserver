import Application
import Contracts
import Foundation
import Errors

public enum RuntimeLifecycleCommand: Equatable {
    case install
    case installProvision(URL)
    case preinstallCheck(URL)
    case status
    case health
    case guestLogSync
    case watchdog
    case configure(RuntimeConfigureCommand)
    case verifyBundle(URL)
    case verifyUpdateBootstrap(URL)
    case stageBundle(URL)
    case applyBundle(RuntimeApplyBundleCommand)
    case applyUpdateBootstrap(RuntimeApplyUpdateBootstrapCommand)
    case resumeUpdateBootstrapHandoff(
        RuntimeUpdateBootstrapRecoveryCommand
    )
    case settleUpdateBootstrapHandoff(
        RuntimeUpdateBootstrapRecoveryCommand
    )
    case proveUpdateBootstrap(RuntimeProveUpdateBootstrapCommand)
    case failUpdateBootstrap(RuntimeFailUpdateBootstrapCommand)
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
    case stopPackageServices
    case guestStackStatus(RuntimeGuestControlReadCommand)
    case guestServiceStart(RuntimeGuestServiceControlCommand)
    case guestServiceStop(RuntimeGuestServiceControlCommand)
    case guestServiceRestart(RuntimeGuestServiceControlCommand)
    case vitalDB(RuntimeVitalDBReadCommand)
    case lab(RuntimeLabControlCommand)
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
            return .installProvision(try requiredPackageInstallContractURL(in: remaining))
        case "preinstall-check":
            return .preinstallCheck(try requiredPackageInstallContractURL(in: remaining))
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
        case "verify-update-bootstrap":
            return .verifyUpdateBootstrap(try requiredBundleURL(
                in: remaining,
                usage:
                    "usage: vitalserver-vm runtime verify-update-bootstrap <bundle.tar.gz>"
            ))
        case "stage-bundle":
            return .stageBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime stage-bundle <bundle.tar.gz>"
            ))
        case "apply-bundle":
            return .applyBundle(try parseApplyBundleCommand(remaining))
        case "apply-update-bootstrap":
            return .applyUpdateBootstrap(
                try parseApplyUpdateBootstrapCommand(remaining)
            )
        case "resume-update-bootstrap-handoff":
            return .resumeUpdateBootstrapHandoff(
                try parseUpdateBootstrapRecoveryCommand(
                    remaining,
                    usage:
                        "usage: vitalserver-vm runtime resume-update-bootstrap-handoff <update-id>"
                )
            )
        case "settle-update-bootstrap-handoff":
            return .settleUpdateBootstrapHandoff(
                try parseUpdateBootstrapRecoveryCommand(
                    remaining,
                    usage:
                        "usage: vitalserver-vm runtime settle-update-bootstrap-handoff <update-id>"
                )
            )
        case "prove-update-bootstrap":
            return .proveUpdateBootstrap(
                try parseProveUpdateBootstrapCommand(remaining)
            )
        case "fail-update-bootstrap":
            return .failUpdateBootstrap(
                try parseFailUpdateBootstrapCommand(remaining)
            )
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
        case "stop-package-services":
            return .stopPackageServices
        case "guest-stack-status":
            return .guestStackStatus(try parseGuestControlReadCommand(
                remaining,
                usage: "usage: vitalserver-vm runtime guest-stack-status [--guest-control-url <url>]"
            ))
        case "guest-service-start":
            return .guestServiceStart(try parseGuestServiceControlCommand(
                remaining,
                usage: "usage: vitalserver-vm runtime guest-service-start <service> [--guest-control-url <url>]"
            ))
        case "guest-service-stop":
            return .guestServiceStop(try parseGuestServiceControlCommand(
                remaining,
                usage: "usage: vitalserver-vm runtime guest-service-stop <service> [--guest-control-url <url>]"
            ))
        case "guest-service-restart":
            return .guestServiceRestart(try parseGuestServiceControlCommand(
                remaining,
                usage: "usage: vitalserver-vm runtime guest-service-restart <service> [--guest-control-url <url>]"
            ))
        case "vitaldb-observation":
            return .vitalDB(try RuntimeVitalDBReadCommand.parseObservationCommand(remaining))
        case "vitaldb-recorders":
            return .vitalDB(try RuntimeVitalDBReadCommand.parseRecordersCommand(remaining))
        case "vitaldb-recorder-activity":
            return .vitalDB(try RuntimeVitalDBReadCommand.parseRecorderActivityCommand(remaining))
        case "vitaldb-beds":
            return .vitalDB(try RuntimeVitalDBReadCommand.parseBedsCommand(remaining))
        case "vitaldb-relationships":
            return .vitalDB(try RuntimeVitalDBReadCommand.parseRelationshipsCommand(remaining))
        case "lab-scenarios":
            return .lab(try RuntimeLabControlCommand.parseScenariosCommand(remaining))
        case "lab-beds":
            return .lab(try RuntimeLabControlCommand.parseBedsCommand(remaining))
        case "lab-recorders":
            return .lab(try RuntimeLabControlCommand.parseRecordersCommand(remaining))
        case "lab-session-create":
            return .lab(try RuntimeLabControlCommand.parseSessionCreateCommand(remaining))
        case "lab-session-get":
            return .lab(try RuntimeLabControlCommand.parseSessionIDCommand(
                remaining,
                action: RuntimeLabControlAction.getSession,
                usage: "usage: vitalserver-vm runtime lab-session-get <session-id> [--guest-control-url <url>]"
            ))
        case "lab-session-start":
            return .lab(try RuntimeLabControlCommand.parseSessionIDCommand(
                remaining,
                action: RuntimeLabControlAction.startSession,
                usage: "usage: vitalserver-vm runtime lab-session-start <session-id> [--guest-control-url <url>]"
            ))
        case "lab-session-stop":
            return .lab(try RuntimeLabControlCommand.parseSessionIDCommand(
                remaining,
                action: RuntimeLabControlAction.stopSession,
                usage: "usage: vitalserver-vm runtime lab-session-stop <session-id> [--guest-control-url <url>]"
            ))
        case "lab-session-finish":
            return .lab(try RuntimeLabControlCommand.parseSessionIDCommand(
                remaining,
                action: RuntimeLabControlAction.finishSession,
                usage: "usage: vitalserver-vm runtime lab-session-finish <session-id> [--guest-control-url <url>]"
            ))
        case "lab-vital-replay":
            return .lab(try RuntimeLabControlCommand.parseVitalReplayCommand(remaining))
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
      vitalserver-vm runtime install-provision --package-install-contract <path>
      vitalserver-vm runtime preinstall-check --package-install-contract <path>
      vitalserver-vm runtime status
      vitalserver-vm runtime health
      vitalserver-vm runtime guest-log-sync
      vitalserver-vm runtime watchdog
      vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--disk-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--runtime-control-port <port>] [--vital-files-dir <path>] [--vitalserver-url <url>] [--remote-console-url <url>] [--public-host <host>] [--public-port <port>] [--recorder-ingress-send-data-mode passthrough|observe_only|mirror_spool|spool_only|spool_and_replay] [--recorder-ingress-send-data-replay-batch-size <count>] [--recorder-ingress-send-data-replay-max-mib-per-second <count>] [--container-memory-limits true|false] [--vitalserver-container-memory-limit-mib <mib>] [--recorder-ingress-container-memory-limit-mib <mib>] [--redis-container-memory-limit-mib <mib>] [--admin-password <password>] [--start-on-boot true|false] [--auto-recovery true|false] [--prevent-system-sleep true|false] [--automatic-backup true|false] [--backup-schedule-times HH:mm[,HH:mm]] [--backup-retention <count>] [--log-archive-retention-days <days>] [--log-archive-maximum-gib <gib>] [--restart|--restart-vm-runtime]
      vitalserver-vm runtime configure [--admin-password-file <path>] [--restart|--restart-vm-runtime]
      vitalserver-vm runtime verify-bundle <bundle.tar.gz>
      vitalserver-vm runtime stage-bundle <bundle.tar.gz>
      vitalserver-vm runtime apply-bundle <bundle.tar.gz> [--allow-unsigned-dev-bundle]
      vitalserver-vm runtime apply-update-bootstrap <bundle.tar.gz> --request-id <id>
      vitalserver-vm runtime resume-update-bootstrap-handoff <update-id>
      vitalserver-vm runtime settle-update-bootstrap-handoff <update-id>
      vitalserver-vm runtime prove-update-bootstrap <update-id> --expect succeeded|failed-rolled-back --timeout-seconds <seconds> --poll-interval-milliseconds <milliseconds>
      vitalserver-vm runtime fail-update-bootstrap <update-id> --reason <reason>
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
      vitalserver-vm runtime stop-package-services
      vitalserver-vm runtime guest-stack-status [--guest-control-url <url>]
      vitalserver-vm runtime guest-service-start <service> [--guest-control-url <url>]
      vitalserver-vm runtime guest-service-stop <service> [--guest-control-url <url>]
      vitalserver-vm runtime guest-service-restart <service> [--guest-control-url <url>]
      vitalserver-vm runtime vitaldb-observation [--guest-control-url <url>]
      vitalserver-vm runtime vitaldb-recorders [--guest-control-url <url>]
      vitalserver-vm runtime vitaldb-recorder-activity <vrcode> [--guest-control-url <url>]
      vitalserver-vm runtime vitaldb-beds [--guest-control-url <url>]
      vitalserver-vm runtime vitaldb-relationships [--guest-control-url <url>]
      vitalserver-vm runtime lab-scenarios [--guest-control-url <url>]
      vitalserver-vm runtime lab-beds [--guest-control-url <url>]
      vitalserver-vm runtime lab-recorders [--guest-control-url <url>]
      vitalserver-vm runtime lab-session-create <scenario-id> [--name <name>] [--recorder-count <count>] [--target-url <url>] [--guest-control-url <url>]
      vitalserver-vm runtime lab-session-get <session-id> [--guest-control-url <url>]
      vitalserver-vm runtime lab-session-start <session-id> [--guest-control-url <url>]
      vitalserver-vm runtime lab-session-stop <session-id> [--guest-control-url <url>]
      vitalserver-vm runtime lab-session-finish <session-id> [--guest-control-url <url>]
      vitalserver-vm runtime lab-vital-replay <vital-file-path> [--session-name <name>] [--target-url <url>] [--guest-control-url <url>]
      vitalserver-vm runtime uninstall [--clean|--force-clean|--force-clean-uninstaller]
    """

    private static func requiredBundleURL(in arguments: [String], usage: String) throws -> URL {
        guard let bundlePath = arguments.first else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return URL(fileURLWithPath: bundlePath)
    }

    private static func parseApplyBundleCommand(
        _ arguments: [String]
    ) throws -> RuntimeApplyBundleCommand {
        let usage = "usage: vitalserver-vm runtime apply-bundle <bundle.tar.gz> [--allow-unsigned-dev-bundle]"
        guard arguments.count == 1 || arguments.count == 2,
              let bundlePath = arguments.first,
              !bundlePath.isEmpty,
              bundlePath != "--allow-unsigned-dev-bundle"
        else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        let intent: RuntimeUpdateApplyTrustIntent
        if arguments.count == 2 {
            guard arguments[1] == "--allow-unsigned-dev-bundle" else {
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
            intent = .allowUnsignedDevelopmentBundle
        } else {
            intent = .requireVerifiedPublisher
        }
        return RuntimeApplyBundleCommand(
            bundleURL: URL(fileURLWithPath: bundlePath),
            trustIntent: intent
        )
    }

    private static func parseApplyUpdateBootstrapCommand(
        _ arguments: [String]
    ) throws -> RuntimeApplyUpdateBootstrapCommand {
        let usage = "usage: vitalserver-vm runtime apply-update-bootstrap <bundle.tar.gz> --request-id <id>"
        guard let bundlePath = arguments.first,
              !bundlePath.isEmpty,
              bundlePath != "--request-id" else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        var requestId: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            guard argument == "--request-id",
                  index + 1 < arguments.count,
                  requestId == nil else {
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
            requestId = arguments[index + 1]
            index += 2
        }
        guard let requestId, !requestId.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return RuntimeApplyUpdateBootstrapCommand(
            bundleURL: URL(fileURLWithPath: bundlePath),
            requestId: requestId
        )
    }

    private static func parseUpdateBootstrapRecoveryCommand(
        _ arguments: [String],
        usage: String
    ) throws -> RuntimeUpdateBootstrapRecoveryCommand {
        guard arguments.count == 1,
              let updateId = arguments.first,
              !updateId.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return RuntimeUpdateBootstrapRecoveryCommand(updateId: updateId)
    }

    private static func parseProveUpdateBootstrapCommand(
        _ arguments: [String]
    ) throws -> RuntimeProveUpdateBootstrapCommand {
        let usage =
            "usage: vitalserver-vm runtime prove-update-bootstrap <update-id> --expect succeeded|failed-rolled-back --timeout-seconds <seconds> --poll-interval-milliseconds <milliseconds>"
        guard arguments.count == 7,
              !arguments[0].isEmpty,
              arguments[1] == "--expect",
              let expectation = UpdateBootstrapLifecycleProofExpectation(
                rawValue: arguments[2]
              ),
              arguments[3] == "--timeout-seconds",
              let timeoutSeconds = UInt64(arguments[4]),
              timeoutSeconds > 0,
              timeoutSeconds <= UInt64.max / 1_000,
              arguments[5] == "--poll-interval-milliseconds",
              let pollIntervalMilliseconds = UInt64(arguments[6]),
              pollIntervalMilliseconds > 0 else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return RuntimeProveUpdateBootstrapCommand(
            updateId: arguments[0],
            expectation: expectation,
            timeoutMilliseconds: timeoutSeconds * 1_000,
            pollIntervalMilliseconds: pollIntervalMilliseconds
        )
    }

    private static func parseFailUpdateBootstrapCommand(
        _ arguments: [String]
    ) throws -> RuntimeFailUpdateBootstrapCommand {
        let usage =
            "usage: vitalserver-vm runtime fail-update-bootstrap <update-id> --reason <reason>"
        guard arguments.count == 3,
              !arguments[0].isEmpty,
              arguments[1] == "--reason",
              !arguments[2].isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return RuntimeFailUpdateBootstrapCommand(
            updateId: arguments[0],
            reason: arguments[2]
        )
    }

    private static func requiredPackageInstallContractURL(in arguments: [String]) throws -> URL {
        let usage = "usage: vitalserver-vm runtime install-provision|preinstall-check --package-install-contract <path>"
        guard arguments.count == 2,
              arguments[0] == "--package-install-contract",
              !arguments[1].isEmpty
        else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        return URL(fileURLWithPath: arguments[1])
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

    private static func parseGuestServiceControlCommand(
        _ arguments: [String],
        usage: String
    ) throws -> RuntimeGuestServiceControlCommand {
        guard let service = arguments.first, !service.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        var remaining = Array(arguments.dropFirst())
        var guestControlBaseURL = RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            switch key {
            case "--guest-control-url":
                guard let value = remaining.first, !value.isEmpty else {
                    throw RuntimeLifecycleCommandParseError.missingArgument("missing value for --guest-control-url")
                }
                remaining.removeFirst()
                guestControlBaseURL = value
            default:
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
        }
        return RuntimeGuestServiceControlCommand(
            service: service,
            guestControlBaseURL: guestControlBaseURL
        )
    }

    private static func parseGuestControlReadCommand(
        _ arguments: [String],
        usage: String
    ) throws -> RuntimeGuestControlReadCommand {
        var remaining = arguments
        var guestControlBaseURL = RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            switch key {
            case "--guest-control-url":
                guard let value = remaining.first, !value.isEmpty else {
                    throw RuntimeLifecycleCommandParseError.missingArgument("missing value for --guest-control-url")
                }
                remaining.removeFirst()
                guestControlBaseURL = value
            default:
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
        }
        return RuntimeGuestControlReadCommand(guestControlBaseURL: guestControlBaseURL)
    }

    private static func parseConfigureCommand(_ arguments: [String]) throws -> RuntimeConfigureCommand {
        var remaining = arguments
        var changes: [RuntimeConfigureChange] = []
        var activation = ConfigureRuntimeActivationIntent.saveOnly

        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            let option = RuntimeConfigureOption(rawValue: key)
            if option == .restart {
                guard activation == .saveOnly else {
                    throw RuntimeLifecycleCommandParseError.missingArgument(
                        "--restart and --restart-vm-runtime are mutually exclusive"
                    )
                }
                activation = .activateChangedComponents
                continue
            }
            if option == .restartVMRuntime {
                guard activation == .saveOnly else {
                    throw RuntimeLifecycleCommandParseError.missingArgument(
                        "--restart and --restart-vm-runtime are mutually exclusive"
                    )
                }
                activation = .restartVMRuntime
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

        return RuntimeConfigureCommand(changes: changes, activation: activation)
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
        case .runtimeControlPort:
            guard let port = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--runtime-control-port must be an integer")
            }
            return .runtimeControlPort(port)
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
        case .recorderIngressSendDataMode:
            guard let mode = RuntimeRecorderIngressSendDataMode(rawValue: value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--recorder-ingress-send-data-mode must be passthrough, observe_only, mirror_spool, spool_only, or spool_and_replay"
                )
            }
            return .recorderIngressSendDataMode(mode)
        case .recorderIngressSendDataReplayBatchSize:
            guard let batchSize = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--recorder-ingress-send-data-replay-batch-size must be an integer"
                )
            }
            return .recorderIngressSendDataReplayBatchSize(batchSize)
        case .recorderIngressSendDataReplayMaxMiBPerSecond:
            guard let maxMiBPerSecond = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--recorder-ingress-send-data-replay-max-mib-per-second must be an integer"
                )
            }
            return .recorderIngressSendDataReplayMaxMiBPerSecond(maxMiBPerSecond)
        case .recorderIngressSettingsFile:
            return .recorderIngressSettingsFile(URL(fileURLWithPath: value))
        case .containerMemoryLimitsEnabled:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument("--container-memory-limits must be true or false")
            }
            return .containerMemoryLimitsEnabled(enabled)
        case .vitalServerContainerMemoryLimitMiB:
            guard let limitMiB = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--vitalserver-container-memory-limit-mib must be an integer"
                )
            }
            return .vitalServerContainerMemoryLimitMiB(limitMiB)
        case .recorderIngressContainerMemoryLimitMiB:
            guard let limitMiB = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--recorder-ingress-container-memory-limit-mib must be an integer"
                )
            }
            return .recorderIngressContainerMemoryLimitMiB(limitMiB)
        case .redisContainerMemoryLimitMiB:
            guard let limitMiB = Int(value) else {
                throw RuntimeLifecycleCommandParseError.missingArgument(
                    "--redis-container-memory-limit-mib must be an integer"
                )
            }
            return .redisContainerMemoryLimitMiB(limitMiB)
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
        case .restart:
            throw RuntimeLifecycleCommandParseError.missingArgument("--restart does not accept a value")
        case .restartVMRuntime:
            throw RuntimeLifecycleCommandParseError.missingArgument("--restart-vm-runtime does not accept a value")
        case .unknown(let key):
            throw RuntimeLifecycleCommandParseError.missingArgument("unsupported runtime configure option: \(key)")
        }
    }
}

public struct RuntimeApplyBundleCommand: Equatable {
    public let bundleURL: URL
    public let trustIntent: RuntimeUpdateApplyTrustIntent

    public init(bundleURL: URL, trustIntent: RuntimeUpdateApplyTrustIntent) {
        self.bundleURL = bundleURL
        self.trustIntent = trustIntent
    }
}
