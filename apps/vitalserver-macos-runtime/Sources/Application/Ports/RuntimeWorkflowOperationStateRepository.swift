import Contracts
import Foundation

public struct RuntimeWorkflowOperationState: Codable, Equatable, Sendable {
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

public struct RuntimeWorkflowOperationStateMutation: Equatable, Sendable {
    public let operationID: String
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let currentStep: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let message: String
    public let reasonCodes: [String]
    public let occurredAt: String
    public let completedAt: String?
    public let expectedRevision: Int?

    public init(
        operationID: String,
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        currentStep: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String] = [],
        occurredAt: String,
        completedAt: String? = nil,
        expectedRevision: Int? = nil
    ) {
        self.operationID = operationID
        self.operation = operation
        self.phase = phase
        self.currentStep = currentStep
        self.stepStatus = stepStatus
        self.message = message
        self.reasonCodes = reasonCodes
        self.occurredAt = occurredAt
        self.completedAt = completedAt
        self.expectedRevision = expectedRevision
    }
}

public enum RuntimeWorkflowOperationStateReadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeWorkflowOperationState)
    case failed(String)
}

public protocol RuntimeWorkflowOperationStateReading: Sendable {
    func loadOperationState(operationID: String) -> RuntimeWorkflowOperationStateReadResult
    func loadLatestOperationState() -> RuntimeWorkflowOperationStateReadResult
    func loadLatestOperationState(operation: RuntimeOperation) -> RuntimeWorkflowOperationStateReadResult
}

public protocol RuntimeWorkflowOperationStateMutating: Sendable {
    @discardableResult
    func saveOperationState(
        _ mutation: RuntimeWorkflowOperationStateMutation
    ) throws -> RuntimeWorkflowOperationState
}

public protocol RuntimeWorkflowOperationStateRepository:
    RuntimeWorkflowOperationStateReading,
    RuntimeWorkflowOperationStateMutating
{}
