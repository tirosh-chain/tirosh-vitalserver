import Application
import Contracts
import XCTest

final class PersistRuntimeWorkflowOperationStateUseCaseTests: XCTestCase {
    func testPersistsStartProgressAndCompletionWithCompareAndSwapRevisions() throws {
        let repository = WorkflowOperationStateRepositorySpy()
        let useCase = PersistRuntimeWorkflowOperationStateUseCase()

        let started = try useCase.start(
            repository: repository,
            operationID: "operation-1",
            operation: .applyBundle,
            message: "starting",
            occurredAt: "2026-07-14T01:00:00Z"
        )
        let progressed = try useCase.record(
            repository: repository,
            operationID: "operation-1",
            event: RuntimeStepExecutionEvent(
                operation: .applyBundle,
                status: .updating,
                step: .stopRuntimeServices,
                stepStatus: .started,
                phase: .running,
                message: "step started"
            ),
            occurredAt: "2026-07-14T01:00:01Z"
        )
        let completed = try useCase.complete(
            repository: repository,
            operationID: "operation-1",
            message: "complete",
            occurredAt: "2026-07-14T01:00:02Z"
        )

        XCTAssertEqual(started.revision, 1)
        XCTAssertEqual(progressed.revision, 2)
        XCTAssertEqual(completed.revision, 3)
        XCTAssertEqual(completed.phase, .completed)
        XCTAssertEqual(completed.completedAt, "2026-07-14T01:00:02Z")
        XCTAssertEqual(repository.mutations.map(\.expectedRevision), [nil, 1, 2])
    }

    func testReportsMissingAndFailedReadsExplicitly() throws {
        let missingRepository = WorkflowOperationStateRepositorySpy()
        let missingUseCase = PersistRuntimeWorkflowOperationStateUseCase()
        XCTAssertThrowsError(try missingUseCase.complete(
            repository: missingRepository,
            operationID: "missing",
            message: "complete",
            occurredAt: "now"
        )) { error in
            XCTAssertEqual(
                error as? PersistRuntimeWorkflowOperationStateError,
                .missing(operationID: "missing")
            )
        }

        let failedRepository = WorkflowOperationStateRepositorySpy()
        failedRepository.readFailure = "database unreadable"
        let failedUseCase = PersistRuntimeWorkflowOperationStateUseCase()
        XCTAssertThrowsError(try failedUseCase.complete(
            repository: failedRepository,
            operationID: "operation-1",
            message: "complete",
            occurredAt: "now"
        )) { error in
            XCTAssertEqual(
                error as? PersistRuntimeWorkflowOperationStateError,
                .readFailed(operationID: "operation-1", reason: "database unreadable")
            )
        }
    }
}

private final class WorkflowOperationStateRepositorySpy:
    RuntimeWorkflowOperationStateRepository,
    @unchecked Sendable
{
    var states: [String: RuntimeWorkflowOperationState] = [:]
    var mutations: [RuntimeWorkflowOperationStateMutation] = []
    var readFailure: String?

    func loadOperationState(operationID: String) -> RuntimeWorkflowOperationStateReadResult {
        if let readFailure {
            return .failed(readFailure)
        }
        return states[operationID].map(RuntimeWorkflowOperationStateReadResult.loaded) ?? .missing
    }

    func loadLatestOperationState(operation: RuntimeOperation) -> RuntimeWorkflowOperationStateReadResult {
        if let readFailure {
            return .failed(readFailure)
        }
        return states.values
            .filter { $0.operation == operation }
            .sorted { $0.revision > $1.revision }
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
