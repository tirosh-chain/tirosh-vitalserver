import Foundation

public enum RuntimeEventType: Codable, Equatable, Sendable {
    case statusChanged
    case progressUpdated
    case healthObserved
    case recoveryTriggered
    case recoveryCompleted
    case containerObserved
    case auditProxyObserved
    case vitalDBObserved
    case vitalDBObserverUnhealthy
    case vitalDBAnomalyDetected
    case runtimeCommandStarted
    case runtimeCommandCompleted
    case runtimeCommandFailed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "status-changed":
            self = .statusChanged
        case "progress-updated":
            self = .progressUpdated
        case "health-observed":
            self = .healthObserved
        case "recovery-triggered":
            self = .recoveryTriggered
        case "recovery-completed":
            self = .recoveryCompleted
        case "container-observed":
            self = .containerObserved
        case "audit-proxy-observed":
            self = .auditProxyObserved
        case "vitaldb-observed":
            self = .vitalDBObserved
        case "vitaldb-observer-unhealthy":
            self = .vitalDBObserverUnhealthy
        case "vitaldb-anomaly-detected":
            self = .vitalDBAnomalyDetected
        case "runtime-command-started":
            self = .runtimeCommandStarted
        case "runtime-command-completed":
            self = .runtimeCommandCompleted
        case "runtime-command-failed":
            self = .runtimeCommandFailed
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
        case .healthObserved:
            return "health-observed"
        case .recoveryTriggered:
            return "recovery-triggered"
        case .recoveryCompleted:
            return "recovery-completed"
        case .containerObserved:
            return "container-observed"
        case .auditProxyObserved:
            return "audit-proxy-observed"
        case .vitalDBObserved:
            return "vitaldb-observed"
        case .vitalDBObserverUnhealthy:
            return "vitaldb-observer-unhealthy"
        case .vitalDBAnomalyDetected:
            return "vitaldb-anomaly-detected"
        case .runtimeCommandStarted:
            return "runtime-command-started"
        case .runtimeCommandCompleted:
            return "runtime-command-completed"
        case .runtimeCommandFailed:
            return "runtime-command-failed"
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
    public let vmState: RuntimeVMState?
    public let vmErrors: [RuntimeVMError]?
    public let failureReasons: [RuntimeFailureReason]
    public let containerObservation: RuntimeContainerObservation?
    public let vitalDBObservation: VitalDBObservationDocument?
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
        vmState: RuntimeVMState? = nil,
        vmErrors: [RuntimeVMError]? = nil,
        failureReasons: [RuntimeFailureReason],
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
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
        self.vmState = vmState
        self.vmErrors = vmErrors
        self.failureReasons = failureReasons
        self.containerObservation = containerObservation
        self.vitalDBObservation = vitalDBObservation
        self.progress = progress
    }
}
