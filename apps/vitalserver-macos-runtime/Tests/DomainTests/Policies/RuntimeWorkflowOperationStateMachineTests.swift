import Contracts
import Domain
import XCTest

final class RuntimeWorkflowOperationStateMachineTests: XCTestCase {
    private let stateMachine = RuntimeWorkflowOperationStateMachine()

    func testStartsNewOperationInPreparingPhase() throws {
        let decision = try stateMachine.transition(
            current: nil,
            event: .started(operationID: "operation-1", operation: .applyBundle, message: "starting")
        )

        XCTAssertEqual(decision.operationID, "operation-1")
        XCTAssertEqual(decision.operation, .applyBundle)
        XCTAssertEqual(decision.phase, .preparing)
        XCTAssertNil(decision.currentStep)
        XCTAssertNil(decision.stepStatus)
        XCTAssertNil(decision.expectedRevision)
        XCTAssertFalse(decision.completed)
    }

    func testProgressRequiresMatchingActiveOperationAndCarriesRevision() throws {
        let decision = try stateMachine.transition(
            current: activeState(revision: 4),
            event: .progressed(progressEvent())
        )

        XCTAssertEqual(decision.phase, .running)
        XCTAssertEqual(decision.currentStep, .stopRuntimeServices)
        XCTAssertEqual(decision.stepStatus, .started)
        XCTAssertEqual(decision.expectedRevision, 4)
        XCTAssertFalse(decision.completed)
    }

    func testCompletionClearsStepAndMarksTerminal() throws {
        let decision = try stateMachine.transition(
            current: activeState(revision: 2),
            event: .completed(message: "complete")
        )

        XCTAssertEqual(decision.phase, .completed)
        XCTAssertNil(decision.currentStep)
        XCTAssertNil(decision.stepStatus)
        XCTAssertEqual(decision.expectedRevision, 2)
        XCTAssertTrue(decision.completed)
    }

    func testFailurePreservesLastExplicitStepAndReasonCodes() throws {
        let current = RuntimeWorkflowOperationTransitionState(
            operationID: "operation-1",
            operation: .applyBundle,
            phase: .running,
            currentStep: .replaceRootfsBase,
            stepStatus: .started,
            revision: 3
        )

        let decision = try stateMachine.transition(
            current: current,
            event: .failed(message: "replacement failed", reasonCodes: ["replace-failed"])
        )

        XCTAssertEqual(decision.phase, .failed)
        XCTAssertEqual(decision.currentStep, .replaceRootfsBase)
        XCTAssertEqual(decision.stepStatus, .started)
        XCTAssertEqual(decision.reasonCodes, ["replace-failed"])
        XCTAssertTrue(decision.completed)
    }

    func testRejectsTransitionAfterTerminalState() {
        let terminal = RuntimeWorkflowOperationTransitionState(
            operationID: "operation-1",
            operation: .applyBundle,
            phase: .completed,
            currentStep: nil,
            stepStatus: nil,
            revision: 5
        )

        XCTAssertThrowsError(try stateMachine.transition(
            current: terminal,
            event: .progressed(progressEvent())
        )) { error in
            XCTAssertEqual(
                error as? RuntimeWorkflowOperationTransitionError,
                .terminalState("completed")
            )
        }
    }

    func testRejectsMismatchedOperationAndInvalidFailedProgress() {
        let rollbackProgress = RuntimeStepExecutionEvent(
            operation: .rollback,
            status: .recovering,
            step: .rollbackStopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "started"
        )
        XCTAssertThrowsError(try stateMachine.transition(
            current: activeState(),
            event: .progressed(rollbackProgress)
        )) { error in
            XCTAssertEqual(
                error as? RuntimeWorkflowOperationTransitionError,
                .operationMismatch(expected: "apply-bundle", actual: "rollback")
            )
        }

        let invalidFailure = RuntimeStepExecutionEvent(
            operation: .applyBundle,
            status: .updating,
            step: .stopRuntimeServices,
            stepStatus: .failed,
            phase: .running,
            message: "failed"
        )
        XCTAssertThrowsError(try stateMachine.transition(
            current: activeState(),
            event: .progressed(invalidFailure)
        ))
    }

    private func activeState(revision: Int = 1) -> RuntimeWorkflowOperationTransitionState {
        RuntimeWorkflowOperationTransitionState(
            operationID: "operation-1",
            operation: .applyBundle,
            phase: .preparing,
            currentStep: nil,
            stepStatus: nil,
            revision: revision
        )
    }

    private func progressEvent() -> RuntimeStepExecutionEvent {
        RuntimeStepExecutionEvent(
            operation: .applyBundle,
            status: .updating,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "started"
        )
    }
}
