import Application
import Contracts

final class RuntimeWorkflowOperationStateRepositorySpy:
    RuntimeWorkflowOperationStateRepository,
    @unchecked Sendable
{
    var states: [String: RuntimeWorkflowOperationState] = [:]
    var mutations: [RuntimeWorkflowOperationStateMutation] = []
    var saveError: Error?

    func loadOperationState(operationID: String) -> RuntimeWorkflowOperationStateReadResult {
        states[operationID].map(RuntimeWorkflowOperationStateReadResult.loaded) ?? .missing
    }

    func loadLatestOperationState(operation: RuntimeOperation) -> RuntimeWorkflowOperationStateReadResult {
        states.values
            .filter { $0.operation == operation }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
            .map(RuntimeWorkflowOperationStateReadResult.loaded) ?? .missing
    }

    func loadLatestOperationState() -> RuntimeWorkflowOperationStateReadResult {
        states.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
            .map(RuntimeWorkflowOperationStateReadResult.loaded) ?? .missing
    }

    func saveOperationState(
        _ mutation: RuntimeWorkflowOperationStateMutation
    ) throws -> RuntimeWorkflowOperationState {
        if let saveError {
            throw saveError
        }
        mutations.append(mutation)
        let existing = states[mutation.operationID]
        let state = RuntimeWorkflowOperationState(
            operationID: mutation.operationID,
            operation: mutation.operation,
            phase: mutation.phase,
            currentStep: mutation.currentStep,
            stepStatus: mutation.stepStatus,
            message: mutation.message,
            reasonCodes: mutation.reasonCodes,
            startedAt: existing?.startedAt ?? mutation.occurredAt,
            updatedAt: mutation.occurredAt,
            completedAt: mutation.completedAt,
            revision: (existing?.revision ?? 0) + 1
        )
        states[state.operationID] = state
        return state
    }
}
