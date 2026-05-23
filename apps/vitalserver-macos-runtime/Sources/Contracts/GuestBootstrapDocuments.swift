import Foundation

public enum GuestBootstrapStatus: Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "running":
            self = .running
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
        case .running:
            return "running"
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

public struct GuestBootstrapResultDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int?
    public let operation: RuntimeOperation?
    public let status: GuestBootstrapStatus
    public let message: String?
    public let reasonCodes: [RuntimeFailureReason]?
    public let updatedAt: String?

    public init(
        schemaVersion: Int? = nil,
        operation: RuntimeOperation? = nil,
        status: GuestBootstrapStatus,
        message: String?,
        reasonCodes: [RuntimeFailureReason]? = nil,
        updatedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.operation = operation
        self.status = status
        self.message = message
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
    }

    public init(
        schemaVersion: Int? = nil,
        operation: String? = nil,
        status: String,
        message: String?,
        reasonCodes: [RuntimeFailureReason]? = nil,
        updatedAt: String?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            operation: operation.map(RuntimeOperation.init(rawValue:)),
            status: GuestBootstrapStatus(rawValue: status),
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt
        )
    }
}
