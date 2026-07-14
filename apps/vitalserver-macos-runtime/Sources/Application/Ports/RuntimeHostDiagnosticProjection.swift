import Contracts
import Foundation

public struct RuntimeHostDiagnosticOutboxEvent: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sequence: Int
    public let eventID: String
    public let aggregateType: String
    public let aggregateID: String
    public let aggregateRevision: Int
    public let eventType: String
    public let occurredAt: String
    public let payloadJSON: String

    public init(
        schemaVersion: Int = 1,
        sequence: Int,
        eventID: String,
        aggregateType: String,
        aggregateID: String,
        aggregateRevision: Int,
        eventType: String,
        occurredAt: String,
        payloadJSON: String
    ) {
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.eventID = eventID
        self.aggregateType = aggregateType
        self.aggregateID = aggregateID
        self.aggregateRevision = aggregateRevision
        self.eventType = eventType
        self.occurredAt = occurredAt
        self.payloadJSON = payloadJSON
    }
}

public struct RuntimeHostDiagnosticProjectionCheckpoint: Equatable, Sendable {
    public let projectionName: String
    public let lastSequence: Int
    public let updatedAt: String
    public let failureAttempts: Int
    public let lastError: String?

    public init(
        projectionName: String,
        lastSequence: Int,
        updatedAt: String,
        failureAttempts: Int,
        lastError: String?
    ) {
        self.projectionName = projectionName
        self.lastSequence = lastSequence
        self.updatedAt = updatedAt
        self.failureAttempts = failureAttempts
        self.lastError = lastError
    }
}

public struct RuntimeHostSettingsDiagnosticSummary: Codable, Equatable, Sendable {
    public let revision: Int
    public let desiredAt: String
    public let materializedRevision: Int?
    public let materializedAt: String?
    public let bootRevision: Int?
    public let bootRunID: String?
    public let bootStartedAt: String?
    public let appliedRevision: Int?
    public let appliedRunID: String?
    public let appliedAt: String?

    public init(
        revision: Int,
        desiredAt: String,
        materializedRevision: Int?,
        materializedAt: String?,
        bootRevision: Int?,
        bootRunID: String?,
        bootStartedAt: String?,
        appliedRevision: Int?,
        appliedRunID: String?,
        appliedAt: String?
    ) {
        self.revision = revision
        self.desiredAt = desiredAt
        self.materializedRevision = materializedRevision
        self.materializedAt = materializedAt
        self.bootRevision = bootRevision
        self.bootRunID = bootRunID
        self.bootStartedAt = bootStartedAt
        self.appliedRevision = appliedRevision
        self.appliedRunID = appliedRunID
        self.appliedAt = appliedAt
    }
}

public struct RuntimeEndpointDiagnosticSummary: Codable, Equatable, Sendable {
    public let revision: Int
    public let runID: String
    public let lifecycleRevision: Int
    public let address: String
    public let source: String
    public let observedAt: String

    public init(
        revision: Int,
        runID: String,
        lifecycleRevision: Int,
        address: String,
        source: String,
        observedAt: String
    ) {
        self.revision = revision
        self.runID = runID
        self.lifecycleRevision = lifecycleRevision
        self.address = address
        self.source = source
        self.observedAt = observedAt
    }
}

public struct RuntimeWorkflowOperationDiagnosticSummary: Codable, Equatable, Sendable {
    public let operationID: String
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let currentStep: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let message: String
    public let reasonCodes: [String]
    public let startedAt: String
    public let updatedAt: String
    public let completedAt: String?
    public let revision: Int

    public init(
        operationID: String,
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        currentStep: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String],
        startedAt: String,
        updatedAt: String,
        completedAt: String?,
        revision: Int
    ) {
        self.operationID = operationID
        self.operation = operation
        self.phase = phase
        self.currentStep = currentStep
        self.stepStatus = stepStatus
        self.message = message
        self.reasonCodes = reasonCodes
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.revision = revision
    }
}

public enum RuntimeHostDiagnosticProjectionNames {
    public static let eventLog = "host-runtime-state-jsonl-v1"
    public static let currentSnapshot = "host-runtime-state-current-json-v1"
}

public struct RuntimeHostStateDiagnosticSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let databaseID: String
    public let databaseSchemaVersion: Int
    public let sourceSequence: Int
    public let generatedAt: String
    public let operationLeaseState: String?
    public let operationLease: RuntimeOperationLeaseDocument?
    public let operationLeaseRevision: Int?
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let vmLifecycleRevision: Int?
    public let runtimeEndpoint: RuntimeEndpointDiagnosticSummary?
    public let hostSettings: RuntimeHostSettingsDiagnosticSummary?
    public let workflowOperations: [RuntimeWorkflowOperationDiagnosticSummary]

    public init(
        schemaVersion: Int = 1,
        databaseID: String,
        databaseSchemaVersion: Int,
        sourceSequence: Int,
        generatedAt: String,
        operationLeaseState: String?,
        operationLease: RuntimeOperationLeaseDocument?,
        operationLeaseRevision: Int?,
        vmLifecycle: RuntimeVMLifecycleDocument?,
        vmLifecycleRevision: Int?,
        runtimeEndpoint: RuntimeEndpointDiagnosticSummary?,
        hostSettings: RuntimeHostSettingsDiagnosticSummary?,
        workflowOperations: [RuntimeWorkflowOperationDiagnosticSummary]
    ) {
        self.schemaVersion = schemaVersion
        self.databaseID = databaseID
        self.databaseSchemaVersion = databaseSchemaVersion
        self.sourceSequence = sourceSequence
        self.generatedAt = generatedAt
        self.operationLeaseState = operationLeaseState
        self.operationLease = operationLease
        self.operationLeaseRevision = operationLeaseRevision
        self.vmLifecycle = vmLifecycle
        self.vmLifecycleRevision = vmLifecycleRevision
        self.runtimeEndpoint = runtimeEndpoint
        self.hostSettings = hostSettings
        self.workflowOperations = workflowOperations
    }
}

public protocol RuntimeHostDiagnosticOutboxReading: Sendable {
    func loadPendingDiagnosticEvents(limit: Int) throws -> [RuntimeHostDiagnosticOutboxEvent]
    func loadDiagnosticProjectionCheckpoint(
        projectionName: String
    ) throws -> RuntimeHostDiagnosticProjectionCheckpoint?
    func loadHostStateDiagnosticSnapshot(generatedAt: String) throws -> RuntimeHostStateDiagnosticSnapshot
}

public protocol RuntimeHostDiagnosticOutboxMutating: Sendable {
    func markDiagnosticEventProjected(
        sequence: Int,
        projectionName: String,
        projectedAt: String
    ) throws
    func markDiagnosticSnapshotProjected(
        sourceSequence: Int,
        projectionName: String,
        projectedAt: String
    ) throws
    func recordDiagnosticProjectionFailure(
        projectionName: String,
        sourceSequence: Int,
        reason: String,
        failedAt: String
    ) throws
}

public protocol RuntimeHostDiagnosticOutboxRepository:
    RuntimeHostDiagnosticOutboxReading,
    RuntimeHostDiagnosticOutboxMutating
{}

public protocol RuntimeHostDiagnosticEventAppending: Sendable {
    func appendDiagnosticEvent(_ event: RuntimeHostDiagnosticOutboxEvent) throws
}

public protocol RuntimeHostStateDiagnosticSnapshotWriting: Sendable {
    func writeHostStateDiagnosticSnapshot(_ snapshot: RuntimeHostStateDiagnosticSnapshot) throws
}
