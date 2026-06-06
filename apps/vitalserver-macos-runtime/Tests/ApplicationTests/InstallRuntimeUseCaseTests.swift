import Application
import Contracts
import Domain
import XCTest
import Errors

final class InstallRuntimeUseCaseTests: XCTestCase {
    func testPlanOwnsFullInstallOperationIntent() {
        let useCase = InstallRuntimeUseCase()

        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .full))

        XCTAssertEqual(plan.mode, .full)
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.install)
        XCTAssertEqual(plan.completionStatus, .healthy)
        XCTAssertEqual(plan.completionMessage, "runtime install completed")
    }

    func testPlanOwnsProvisionInstallOperationIntent() {
        let useCase = InstallRuntimeUseCase()

        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .provision))

        XCTAssertEqual(plan.mode, .provision)
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.installProvision)
        XCTAssertEqual(plan.completionStatus, .degraded)
        XCTAssertEqual(plan.completionMessage, "runtime install provisioned; runtime services starting")
    }

    func testTransitionReturnsExplicitDecisionWithoutPersistingState() throws {
        let useCase = InstallRuntimeUseCase()

        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .full))
        let decision = try useCase.transition(
            from: .notStarted,
            event: .start,
            context: RuntimeInstallTransitionContext(mode: plan.mode, plan: plan.operationPlan),
            expectedCommands: [.loadSettings]
        )

        XCTAssertEqual(decision.state, .started)
        XCTAssertEqual(decision.persistedState, .started)
        XCTAssertEqual(decision.message, "runtime install started")
        XCTAssertEqual(decision.commands, [.loadSettings])
    }

    func testUnexpectedCommandsFailExplicitly() {
        let useCase = InstallRuntimeUseCase()
        let decision = RuntimeInstallTransitionDecision(
            state: .started,
            persistedState: .started,
            commands: [.loadSettings],
            blockers: [],
            message: "unexpected"
        )

        XCTAssertThrowsError(try useCase.requireCommands([], in: decision)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "unexpected install workflow commands state=started expected=[] actual=[Domain.RuntimeInstallWorkflowCommand.loadSettings]"
            )
        }
    }
}
