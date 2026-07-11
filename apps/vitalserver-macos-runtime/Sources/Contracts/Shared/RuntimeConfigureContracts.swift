public enum RuntimeConfigureOption: Equatable, Sendable {
    case cpu
    case memoryGiB
    case diskGiB
    case network
    case bridgedInterface
    case proxyPort
    case runtimeControlPort
    case vitalFilesDirectory
    case vitalServerURL
    case remoteConsoleURL
    case publicHost
    case publicPort
    case recorderIngressSendDataMode
    case recorderIngressSendDataReplayBatchSize
    case recorderIngressSendDataReplayMaxMiBPerSecond
    case recorderIngressSettingsFile
    case containerMemoryLimitsEnabled
    case vitalServerContainerMemoryLimitMiB
    case recorderIngressContainerMemoryLimitMiB
    case redisContainerMemoryLimitMiB
    case adminPassword
    case adminPasswordFile
    case startOnBoot
    case autoRecovery
    case preventSystemSleep
    case automaticBackup
    case backupScheduleTimes
    case backupRetention
    case logArchiveRetentionDays
    case logArchiveMaximumGiB
    case restart
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "--cpu":
            self = .cpu
        case "--memory-gib":
            self = .memoryGiB
        case "--disk-gib":
            self = .diskGiB
        case "--network":
            self = .network
        case "--bridged-interface":
            self = .bridgedInterface
        case "--proxy-port":
            self = .proxyPort
        case "--runtime-control-port":
            self = .runtimeControlPort
        case "--vital-files-dir":
            self = .vitalFilesDirectory
        case "--vitalserver-url":
            self = .vitalServerURL
        case "--remote-console-url":
            self = .remoteConsoleURL
        case "--public-host":
            self = .publicHost
        case "--public-port":
            self = .publicPort
        case "--recorder-ingress-send-data-mode":
            self = .recorderIngressSendDataMode
        case "--recorder-ingress-send-data-replay-batch-size":
            self = .recorderIngressSendDataReplayBatchSize
        case "--recorder-ingress-send-data-replay-max-mib-per-second":
            self = .recorderIngressSendDataReplayMaxMiBPerSecond
        case "--recorder-ingress-settings-file":
            self = .recorderIngressSettingsFile
        case "--container-memory-limits":
            self = .containerMemoryLimitsEnabled
        case "--vitalserver-container-memory-limit-mib":
            self = .vitalServerContainerMemoryLimitMiB
        case "--recorder-ingress-container-memory-limit-mib":
            self = .recorderIngressContainerMemoryLimitMiB
        case "--redis-container-memory-limit-mib":
            self = .redisContainerMemoryLimitMiB
        case "--admin-password":
            self = .adminPassword
        case "--admin-password-file":
            self = .adminPasswordFile
        case "--start-on-boot":
            self = .startOnBoot
        case "--auto-recovery":
            self = .autoRecovery
        case "--prevent-system-sleep":
            self = .preventSystemSleep
        case "--automatic-backup":
            self = .automaticBackup
        case "--backup-schedule-times":
            self = .backupScheduleTimes
        case "--backup-retention":
            self = .backupRetention
        case "--log-archive-retention-days":
            self = .logArchiveRetentionDays
        case "--log-archive-maximum-gib":
            self = .logArchiveMaximumGiB
        case "--restart":
            self = .restart
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .cpu:
            return "--cpu"
        case .memoryGiB:
            return "--memory-gib"
        case .diskGiB:
            return "--disk-gib"
        case .network:
            return "--network"
        case .bridgedInterface:
            return "--bridged-interface"
        case .proxyPort:
            return "--proxy-port"
        case .runtimeControlPort:
            return "--runtime-control-port"
        case .vitalFilesDirectory:
            return "--vital-files-dir"
        case .vitalServerURL:
            return "--vitalserver-url"
        case .remoteConsoleURL:
            return "--remote-console-url"
        case .publicHost:
            return "--public-host"
        case .publicPort:
            return "--public-port"
        case .recorderIngressSendDataMode:
            return "--recorder-ingress-send-data-mode"
        case .recorderIngressSendDataReplayBatchSize:
            return "--recorder-ingress-send-data-replay-batch-size"
        case .recorderIngressSendDataReplayMaxMiBPerSecond:
            return "--recorder-ingress-send-data-replay-max-mib-per-second"
        case .recorderIngressSettingsFile:
            return "--recorder-ingress-settings-file"
        case .containerMemoryLimitsEnabled:
            return "--container-memory-limits"
        case .vitalServerContainerMemoryLimitMiB:
            return "--vitalserver-container-memory-limit-mib"
        case .recorderIngressContainerMemoryLimitMiB:
            return "--recorder-ingress-container-memory-limit-mib"
        case .redisContainerMemoryLimitMiB:
            return "--redis-container-memory-limit-mib"
        case .adminPassword:
            return "--admin-password"
        case .adminPasswordFile:
            return "--admin-password-file"
        case .startOnBoot:
            return "--start-on-boot"
        case .autoRecovery:
            return "--auto-recovery"
        case .preventSystemSleep:
            return "--prevent-system-sleep"
        case .automaticBackup:
            return "--automatic-backup"
        case .backupScheduleTimes:
            return "--backup-schedule-times"
        case .backupRetention:
            return "--backup-retention"
        case .logArchiveRetentionDays:
            return "--log-archive-retention-days"
        case .logArchiveMaximumGiB:
            return "--log-archive-maximum-gib"
        case .restart:
            return "--restart"
        case .unknown(let value):
            return value
        }
    }

    public var requiresValue: Bool {
        self != .restart
    }
}

public enum RuntimeBooleanParser {
    public static func parse(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }
}

public enum RuntimeTextValidator {
    public static func isSingleLine(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }
}
