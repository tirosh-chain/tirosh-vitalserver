import Foundation

public enum RuntimeUninstallState: Codable, Equatable, Sendable {
    case started
    case vitalServerBackupRequested
    case vitalServerBackupCompleted
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
        case "started": self = .started
        case "vitalserver-backup-requested": self = .vitalServerBackupRequested
        case "vitalserver-backup-completed": self = .vitalServerBackupCompleted
        case "stop-services-requested": self = .stopServicesRequested
        case "service-stop-blocked": self = .serviceStopBlocked
        case "files-removal-started": self = .filesRemovalStarted
        case "files-removal-blocked": self = .filesRemovalBlocked
        case "receipts-forget-started": self = .receiptsForgetStarted
        case "receipts-forget-blocked": self = .receiptsForgetBlocked
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .started: return "started"
        case .vitalServerBackupRequested: return "vitalserver-backup-requested"
        case .vitalServerBackupCompleted: return "vitalserver-backup-completed"
        case .stopServicesRequested: return "stop-services-requested"
        case .serviceStopBlocked: return "service-stop-blocked"
        case .filesRemovalStarted: return "files-removal-started"
        case .filesRemovalBlocked: return "files-removal-blocked"
        case .receiptsForgetStarted: return "receipts-forget-started"
        case .receiptsForgetBlocked: return "receipts-forget-blocked"
        case .completed: return "completed"
        case .failed: return "failed"
        case .unknown(let value): return value
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
