public enum RuntimeConfigureOption: Equatable, Sendable {
    case cpu
    case memoryGiB
    case diskGiB
    case network
    case bridgedInterface
    case proxyPort
    case vitalFilesDirectory
    case publicHost
    case publicPort
    case adminPassword
    case adminPasswordFile
    case startOnBoot
    case autoRecovery
    case redisBackupRetention
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
        case "--vital-files-dir":
            self = .vitalFilesDirectory
        case "--public-host":
            self = .publicHost
        case "--public-port":
            self = .publicPort
        case "--admin-password":
            self = .adminPassword
        case "--admin-password-file":
            self = .adminPasswordFile
        case "--start-on-boot":
            self = .startOnBoot
        case "--auto-recovery":
            self = .autoRecovery
        case "--redis-backup-retention":
            self = .redisBackupRetention
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
        case .vitalFilesDirectory:
            return "--vital-files-dir"
        case .publicHost:
            return "--public-host"
        case .publicPort:
            return "--public-port"
        case .adminPassword:
            return "--admin-password"
        case .adminPasswordFile:
            return "--admin-password-file"
        case .startOnBoot:
            return "--start-on-boot"
        case .autoRecovery:
            return "--auto-recovery"
        case .redisBackupRetention:
            return "--redis-backup-retention"
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
