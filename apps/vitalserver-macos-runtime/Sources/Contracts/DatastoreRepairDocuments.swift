import Foundation

public enum DatastoreRepairStatus: Codable, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed
    case skipped
    case stale
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "running":
            self = .running
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "skipped":
            self = .skipped
        case "stale":
            self = .stale
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .pending:
            return "pending"
        case .running:
            return "running"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        case .stale:
            return "stale"
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

public struct DatastoreRepairResultDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int?
    public let requestId: String?
    public let operation: RuntimeOperation?
    public let status: DatastoreRepairStatus
    public let message: String?
    public let step: String?
    public let reasonCodes: [String]?
    public let updatedAt: String?

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: RuntimeOperation? = nil,
        status: DatastoreRepairStatus,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        updatedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.operation = operation
        self.status = status
        self.message = message
        self.step = step
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
    }

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: String? = nil,
        status: String,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        updatedAt: String?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            requestId: requestId,
            operation: operation.map(RuntimeOperation.init(rawValue:)),
            status: DatastoreRepairStatus(rawValue: status),
            message: message,
            step: step,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt
        )
    }

    public var completed: Bool {
        status == .completed
    }

    public var failed: Bool {
        status == .failed
    }
}
