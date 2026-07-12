import Foundation

public enum RuntimeEventType: Codable, Equatable, Sendable {
    case statusChanged
    case progressUpdated
    case healthObserved
    case recoveryTriggered
    case recoveryCompleted
    case recoverySuppressed
    case recoveryDeferred
    case domainErrorObserved
    case vmErrorObserved
    case containerObserved
    case recorderIngressObserved
    case vitalDBObserved
    case vitalDBObserverUnhealthy
    case vitalDBAnomalyDetected
    case watchdogSkipped
    case recoveryPlanned
    case serviceRestartDispatched
    case observabilityStoreFailed
    case runtimeStatusObserved
    case guestStateObserved
    case runtimeCommandStarted
    case runtimeCommandCompleted
    case runtimeCommandFailed
    case operationAccepted
    case operationRunning
    case operationCompleted
    case operationFailed
    case operationCancelled
    case operationInterrupted
    case unknown(String)

    public static let knownTypes: [RuntimeEventType] = [
        .statusChanged,
        .progressUpdated,
        .healthObserved,
        .recoveryTriggered,
        .recoveryCompleted,
        .recoverySuppressed,
        .recoveryDeferred,
        .domainErrorObserved,
        .vmErrorObserved,
        .containerObserved,
        .recorderIngressObserved,
        .vitalDBObserved,
        .vitalDBObserverUnhealthy,
        .vitalDBAnomalyDetected,
        .watchdogSkipped,
        .recoveryPlanned,
        .serviceRestartDispatched,
        .observabilityStoreFailed,
        .runtimeStatusObserved,
        .guestStateObserved,
        .runtimeCommandStarted,
        .runtimeCommandCompleted,
        .runtimeCommandFailed,
        .operationAccepted,
        .operationRunning,
        .operationCompleted,
        .operationFailed,
        .operationCancelled,
        .operationInterrupted,
    ]

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
        case "recovery-suppressed":
            self = .recoverySuppressed
        case "recovery-deferred":
            self = .recoveryDeferred
        case "domain-error-observed":
            self = .domainErrorObserved
        case "vm-error-observed":
            self = .vmErrorObserved
        case "container-observed":
            self = .containerObserved
        case "recorder-ingress-observed":
            self = .recorderIngressObserved
        case "vitaldb-observed":
            self = .vitalDBObserved
        case "vitaldb-observer-unhealthy":
            self = .vitalDBObserverUnhealthy
        case "vitaldb-anomaly-detected":
            self = .vitalDBAnomalyDetected
        case "watchdog-skipped":
            self = .watchdogSkipped
        case "recovery-planned":
            self = .recoveryPlanned
        case "service-restart-dispatched":
            self = .serviceRestartDispatched
        case "observability-store-failed":
            self = .observabilityStoreFailed
        case "runtime-status-observed":
            self = .runtimeStatusObserved
        case "guest-state-observed":
            self = .guestStateObserved
        case "runtime-command-started":
            self = .runtimeCommandStarted
        case "runtime-command-completed":
            self = .runtimeCommandCompleted
        case "runtime-command-failed":
            self = .runtimeCommandFailed
        case "operation-accepted":
            self = .operationAccepted
        case "operation-running":
            self = .operationRunning
        case "operation-completed":
            self = .operationCompleted
        case "operation-failed":
            self = .operationFailed
        case "operation-cancelled":
            self = .operationCancelled
        case "operation-interrupted":
            self = .operationInterrupted
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
        case .recoverySuppressed:
            return "recovery-suppressed"
        case .recoveryDeferred:
            return "recovery-deferred"
        case .domainErrorObserved:
            return "domain-error-observed"
        case .vmErrorObserved:
            return "vm-error-observed"
        case .containerObserved:
            return "container-observed"
        case .recorderIngressObserved:
            return "recorder-ingress-observed"
        case .vitalDBObserved:
            return "vitaldb-observed"
        case .vitalDBObserverUnhealthy:
            return "vitaldb-observer-unhealthy"
        case .vitalDBAnomalyDetected:
            return "vitaldb-anomaly-detected"
        case .watchdogSkipped:
            return "watchdog-skipped"
        case .recoveryPlanned:
            return "recovery-planned"
        case .serviceRestartDispatched:
            return "service-restart-dispatched"
        case .observabilityStoreFailed:
            return "observability-store-failed"
        case .runtimeStatusObserved:
            return "runtime-status-observed"
        case .guestStateObserved:
            return "guest-state-observed"
        case .runtimeCommandStarted:
            return "runtime-command-started"
        case .runtimeCommandCompleted:
            return "runtime-command-completed"
        case .runtimeCommandFailed:
            return "runtime-command-failed"
        case .operationAccepted:
            return "operation-accepted"
        case .operationRunning:
            return "operation-running"
        case .operationCompleted:
            return "operation-completed"
        case .operationFailed:
            return "operation-failed"
        case .operationCancelled:
            return "operation-cancelled"
        case .operationInterrupted:
            return "operation-interrupted"
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
    public let status: RuntimeStatusLevel?
    public let previousStatus: RuntimeStatusLevel?
    public let operation: RuntimeOperation?
    public let message: String
    public let runtimeVersion: String
    public let vmState: RuntimeVMState?
    public let vmErrors: [RuntimeVMError]?
    public let failureReasons: [RuntimeFailureReason]
    public let domainErrors: [RuntimeDomainError]?
    public let vitalDBObservation: VitalDBObservationDocument?
    public let progress: RuntimeProgressDocument?

    public init(
        schemaVersion: Int = 1,
        id: String,
        source: String = "host-runtime",
        eventType: RuntimeEventType,
        timestamp: String,
        product: String,
        status: RuntimeStatusLevel? = nil,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation? = nil,
        message: String,
        runtimeVersion: String,
        vmState: RuntimeVMState? = nil,
        vmErrors: [RuntimeVMError]? = nil,
        failureReasons: [RuntimeFailureReason],
        domainErrors: [RuntimeDomainError]? = nil,
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
        self.domainErrors = domainErrors ?? (failureReasons.isEmpty ? nil : failureReasons.map(RuntimeDomainError.init))
        self.vitalDBObservation = vitalDBObservation
        self.progress = progress
    }

    public init(
        schemaVersion: Int = 1,
        id: String,
        source: String = "host-runtime",
        eventType: RuntimeEventType,
        timestamp: String,
        product: String,
        status: RuntimeStatusLevel? = nil,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation? = nil,
        message: String,
        runtimeVersion: String,
        vmState: RuntimeVMState? = nil,
        vmErrors: [RuntimeVMError]? = nil,
        failureReasons: [RuntimeFailureReason],
        vitalDBObservation: VitalDBObservationDocument? = nil,
        progress: RuntimeProgressDocument?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            id: id,
            source: source,
            eventType: eventType,
            timestamp: timestamp,
            product: product,
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersion,
            vmState: vmState,
            vmErrors: vmErrors,
            failureReasons: failureReasons,
            domainErrors: nil,
            vitalDBObservation: vitalDBObservation,
            progress: progress
        )
    }
}
