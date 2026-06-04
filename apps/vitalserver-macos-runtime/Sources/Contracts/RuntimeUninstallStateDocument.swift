import Foundation

public enum RuntimeUninstallState: Codable, Equatable, Sendable {
    case started
    case redisBackupRequested
    case redisBackupCompleted
    case stopServicesRequested
    case serviceStopBlocked
    case filesRemovalStarted
    case filesRemovalBlocked
    case receiptsForgetStarted
    case receiptsForgetBlocked
    case completed
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "started":
            self = .started
        case "redis-backup-requested":
            self = .redisBackupRequested
        case "redis-backup-completed":
            self = .redisBackupCompleted
        case "stop-services-requested":
            self = .stopServicesRequested
        case "service-stop-blocked":
            self = .serviceStopBlocked
        case "files-removal-started":
            self = .filesRemovalStarted
        case "files-removal-blocked":
            self = .filesRemovalBlocked
        case "receipts-forget-started":
            self = .receiptsForgetStarted
        case "receipts-forget-blocked":
            self = .receiptsForgetBlocked
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .started:
            return "started"
        case .redisBackupRequested:
            return "redis-backup-requested"
        case .redisBackupCompleted:
            return "redis-backup-completed"
        case .stopServicesRequested:
            return "stop-services-requested"
        case .serviceStopBlocked:
            return "service-stop-blocked"
        case .filesRemovalStarted:
            return "files-removal-started"
        case .filesRemovalBlocked:
            return "files-removal-blocked"
        case .receiptsForgetStarted:
            return "receipts-forget-started"
        case .receiptsForgetBlocked:
            return "receipts-forget-blocked"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RuntimeUninstallStateDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let state: RuntimeUninstallState
    public let clean: Bool
    public let updatedAt: String
    public let message: String?
    public let blockers: [String]

    public init(
        schemaVersion: Int = 1,
        state: RuntimeUninstallState,
        clean: Bool,
        updatedAt: String,
        message: String? = nil,
        blockers: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.clean = clean
        self.updatedAt = updatedAt
        self.message = message
        self.blockers = blockers
    }
}
