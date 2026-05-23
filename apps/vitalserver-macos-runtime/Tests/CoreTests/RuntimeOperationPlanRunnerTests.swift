import Core
import Contracts
import XCTest

final class RuntimeOperationPlanRunnerTests: XCTestCase {
    func testRunsEveryStepAndPublishesStartedThenCompleted() throws {
        let plan = try RuntimeOperationPlan(
            operation: .applyBundle,
            steps: [.stopRuntimeServices, .replaceRootfsBase]
        )
        var executed: [RuntimeWorkflowStep] = []
        var events: [RuntimeStepExecutionEvent] = []

        try RuntimeOperationPlanRunner.run(
            plan: plan,
            status: .updating,
            execute: { step in executed.append(step) },
            publish: { events.append($0) }
        )

        XCTAssertEqual(executed, [.stopRuntimeServices, .replaceRootfsBase])
        XCTAssertEqual(events.map(\.step), [
            .stopRuntimeServices,
            .stopRuntimeServices,
            .replaceRootfsBase,
            .replaceRootfsBase,
        ])
        XCTAssertEqual(events.map(\.stepStatus), [.started, .completed, .started, .completed])
        XCTAssertEqual(events.map(\.phase), [.running, .running, .running, .running])
        XCTAssertEqual(events.map(\.operation), Array(repeating: .applyBundle, count: 4))
        XCTAssertEqual(events.map(\.status), Array(repeating: .updating, count: 4))
        XCTAssertEqual(events[0].message, "step started: stop-runtime-services")
        XCTAssertEqual(events[1].message, "step completed: stop-runtime-services")
    }

    func testStopsOnFailureAndPublishesFailedEvent() {
        let plan = try! RuntimeOperationPlan(
            operation: .rollback,
            steps: [.rollbackStopRuntimeServices, .rollbackRestoreRootfsBase, .rollbackWaitRuntimeHealth]
        )
        var executed: [RuntimeWorkflowStep] = []
        var events: [RuntimeStepExecutionEvent] = []

        XCTAssertThrowsError(try RuntimeOperationPlanRunner.run(
            plan: plan,
            status: .recovering,
            execute: { step in
                executed.append(step)
                if step == .rollbackRestoreRootfsBase {
                    throw PlanRunnerTestError.failed
                }
            },
            publish: { events.append($0) }
        ))

        XCTAssertEqual(executed, [.rollbackStopRuntimeServices, .rollbackRestoreRootfsBase])
        XCTAssertEqual(events.map(\.stepStatus), [.started, .completed, .started, .failed])
        XCTAssertEqual(events.last?.step, .rollbackRestoreRootfsBase)
        XCTAssertEqual(events.last?.phase, .failed)
        XCTAssertEqual(events.last?.message, "step failed: rollback-restore-rootfs-base: failed")
    }

    func testRejectsPlanContainingStepsFromAnotherOperationBeforeExecution() {
        XCTAssertThrowsError(try RuntimeOperationPlan(
            operation: .install,
            steps: [.loadInstallSettings, .replaceRootfsBase]
        )) { error in
            XCTAssertEqual(error as? RuntimeOperationPlanValidationError, RuntimeOperationPlanValidationError(
                operation: .install,
                invalidSteps: [.replaceRootfsBase]
            ))
        }
    }
}

private enum PlanRunnerTestError: Error, CustomStringConvertible {
    case failed

    var description: String {
        "failed"
    }
}
