import Foundation

public enum RuntimeProgressPhase: Codable, Equatable, Sendable {
    case preparing
    case waitingForPrivilege
    case running
    case waiting
    case recovering
    case completed
    case failed
    case cancelled
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "preparing":
            self = .preparing
        case "waiting-for-privilege":
            self = .waitingForPrivilege
        case "running":
            self = .running
        case "waiting":
            self = .waiting
        case "recovering":
            self = .recovering
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "cancelled":
            self = .cancelled
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .preparing:
            return "preparing"
        case .waitingForPrivilege:
            return "waiting-for-privilege"
        case .running:
            return "running"
        case .waiting:
            return "waiting"
        case .recovering:
            return "recovering"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
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

public enum RuntimeProgressStepStatus: Codable, Equatable, Sendable {
    case pending
    case started
    case completed
    case failed
    case skipped
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "started":
            self = .started
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "skipped":
            self = .skipped
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .pending:
            return "pending"
        case .started:
            return "started"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
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

public struct RuntimeProgressDocument: Codable, Equatable, Sendable {
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let step: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let message: String
    public let reasonCodes: [String]
    public let startedAt: String?
    public let updatedAt: String

    public init(
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        step: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String],
        startedAt: String?,
        updatedAt: String
    ) {
        self.operation = operation
        self.phase = phase
        self.step = step
        self.stepStatus = stepStatus
        self.message = message
        self.reasonCodes = reasonCodes
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public init(
        operation: String,
        phase: String,
        step: String?,
        stepStatus: String?,
        message: String,
        reasonCodes: [String],
        startedAt: String?,
        updatedAt: String
    ) {
        self.init(
            operation: RuntimeOperation(rawValue: operation),
            phase: RuntimeProgressPhase(rawValue: phase),
            step: step.map(RuntimeWorkflowStep.init(rawValue:)),
            stepStatus: stepStatus.map(RuntimeProgressStepStatus.init(rawValue:)),
            message: message,
            reasonCodes: reasonCodes,
            startedAt: startedAt,
            updatedAt: updatedAt
        )
    }
}
