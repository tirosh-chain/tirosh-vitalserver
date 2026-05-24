import Foundation

public enum RuntimeEventType: Codable, Equatable, Sendable {
    case statusChanged
    case progressUpdated
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "status-changed":
            self = .statusChanged
        case "progress-updated":
            self = .progressUpdated
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .statusChanged:
            return "status-changed"
        case .progressUpdated:
            return "progress-updated"
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

public struct RuntimeEventDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let source: String
    public let eventType: RuntimeEventType
    public let timestamp: String
    public let product: String
    public let status: RuntimeStatusLevel
    public let previousStatus: RuntimeStatusLevel?
    public let operation: RuntimeOperation
    public let message: String
    public let runtimeVersion: String
    public let failureReasons: [RuntimeFailureReason]
    public let containerObservation: RuntimeContainerObservation?
    public let progress: RuntimeProgressDocument?

    public init(
        schemaVersion: Int = 1,
        id: String,
        source: String = "host-runtime",
        eventType: RuntimeEventType,
        timestamp: String,
        product: String,
        status: RuntimeStatusLevel,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation,
        message: String,
        runtimeVersion: String,
        failureReasons: [RuntimeFailureReason],
        containerObservation: RuntimeContainerObservation? = nil,
        progress: RuntimeProgressDocument?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.source = source
        self.eventType = eventType
        self.timestamp = timestamp
        self.product = product
        self.status = status
        self.previousStatus = previousStatus
        self.operation = operation
        self.message = message
        self.runtimeVersion = runtimeVersion
        self.failureReasons = failureReasons
        self.containerObservation = containerObservation
        self.progress = progress
    }
}
