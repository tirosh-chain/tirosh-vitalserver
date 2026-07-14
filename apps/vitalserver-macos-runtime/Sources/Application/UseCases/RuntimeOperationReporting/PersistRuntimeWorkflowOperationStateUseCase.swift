import Contracts
import Domain

public enum PersistRuntimeWorkflowOperationStateError: Error, Equatable, CustomStringConvertible {
    case readFailed(operationID: String, reason: String)
    case missing(operationID: String)

    public var description: String {
        switch self {
        case .readFailed(let operationID, let reason):
            return "workflow operation state read failed operationId=\(operationID) reason=\(reason)"
        case .missing(let operationID):
            return "workflow operation state is missing operationId=\(operationID)"
        }
    }
}

public struct PersistRuntimeWorkflowOperationStateUseCase {
    public init() {}

    @discardableResult
    public func start(
        repository: any RuntimeWorkflowOperationStateRepository,
        operationID: String,
        operation: RuntimeOperation,
        message: String,
        occurredAt: String
    ) throws -> RuntimeWorkflowOperationState {
        let decision = try RuntimeWorkflowOperationStateMachine().transition(
            current: nil,
            event: .started(operationID: operationID, operation: operation, message: message)
        )
        return try persist(decision, occurredAt: occurredAt, repository: repository)
    }

    @discardableResult
    public func record(
        repository: any RuntimeWorkflowOperationStateRepository,
        operationID: String,
        event: RuntimeStepExecutionEvent,
        occurredAt: String
    ) throws -> RuntimeWorkflowOperationState {
        let state = try load(operationID: operationID, repository: repository)
        let decision = try RuntimeWorkflowOperationStateMachine().transition(
            current: transitionState(state),
            event: .progressed(event)
        )
        return try persist(decision, occurredAt: occurredAt, repository: repository)
    }

    @discardableResult
    public func complete(
        repository: any RuntimeWorkflowOperationStateRepository,
        operationID: String,
        message: String,
        occurredAt: String
    ) throws -> RuntimeWorkflowOperationState {
        let state = try load(operationID: operationID, repository: repository)
        let decision = try RuntimeWorkflowOperationStateMachine().transition(
            current: transitionState(state),
            event: .completed(message: message)
        )
        return try persist(decision, occurredAt: occurredAt, repository: repository)
    }

    @discardableResult
    public func fail(
        repository: any RuntimeWorkflowOperationStateRepository,
        operationID: String,
        message: String,
        reasonCodes: [String],
        occurredAt: String
    ) throws -> RuntimeWorkflowOperationState {
        let state = try load(operationID: operationID, repository: repository)
        let decision = try RuntimeWorkflowOperationStateMachine().transition(
            current: transitionState(state),
            event: .failed(message: message, reasonCodes: reasonCodes)
        )
        guard decision.requiresPersistence else {
            return state
        }
        return try persist(decision, occurredAt: occurredAt, repository: repository)
    }

    @discardableResult
    public func transition(
        repository: any RuntimeWorkflowOperationStateRepository,
        operationID: String,
        event: RuntimeWorkflowOperationTransitionEvent,
        occurredAt: String
    ) throws -> RuntimeWorkflowOperationState {
        let current: RuntimeWorkflowOperationState?
        if case .started = event {
            current = nil
        } else {
            current = try load(operationID: operationID, repository: repository)
        }
        let decision = try RuntimeWorkflowOperationStateMachine().transition(
            current: current.map(transitionState),
            event: event
        )
        if !decision.requiresPersistence, let current {
            return current
        }
        return try persist(decision, occurredAt: occurredAt, repository: repository)
    }

    private func load(
        operationID: String,
        repository: any RuntimeWorkflowOperationStateRepository
    ) throws -> RuntimeWorkflowOperationState {
        switch repository.loadOperationState(operationID: operationID) {
        case .loaded(let state):
            return state
        case .missing:
            throw PersistRuntimeWorkflowOperationStateError.missing(operationID: operationID)
        case .failed(let reason):
            throw PersistRuntimeWorkflowOperationStateError.readFailed(
                operationID: operationID,
                reason: reason
            )
        }
    }

    private func transitionState(
        _ state: RuntimeWorkflowOperationState
    ) -> RuntimeWorkflowOperationTransitionState {
        RuntimeWorkflowOperationTransitionState(
            operationID: state.operationID,
            operation: state.operation,
            phase: state.phase,
            currentStep: state.currentStep,
            stepStatus: state.stepStatus,
            revision: state.revision
        )
    }

    private func persist(
        _ decision: RuntimeWorkflowOperationTransitionDecision,
        occurredAt: String,
        repository: any RuntimeWorkflowOperationStateRepository
    ) throws -> RuntimeWorkflowOperationState {
        try repository.saveOperationState(RuntimeWorkflowOperationStateMutation(
            operationID: decision.operationID,
            operation: decision.operation,
            phase: decision.phase,
            currentStep: decision.currentStep,
            stepStatus: decision.stepStatus,
            message: decision.message,
            reasonCodes: decision.reasonCodes,
            occurredAt: occurredAt,
            completedAt: decision.completed ? occurredAt : nil,
            expectedRevision: decision.expectedRevision
        ))
    }
}
