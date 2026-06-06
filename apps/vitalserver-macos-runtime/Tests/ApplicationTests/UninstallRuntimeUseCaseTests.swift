import Application
import Domain
import XCTest
import Errors

final class UninstallRuntimeUseCaseTests: XCTestCase {
    func testTransitionReturnsExplicitDecisionWithoutPersistingState() throws {
        let useCase = UninstallRuntimeUseCase()

        let decision = try useCase.transition(
            from: .notStarted,
            event: .start(clean: true),
            expectedCommands: []
        )

        XCTAssertEqual(decision.state, .started)
        XCTAssertEqual(decision.persistedState, .started)
        XCTAssertEqual(decision.message, "uninstall started")
        XCTAssertEqual(decision.blockers, [])
    }

    func testBlockedTransitionExpectsNoCommandsAndCarriesBlockers() throws {
        let useCase = UninstallRuntimeUseCase()

        let decision = try useCase.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(RuntimeUninstallReadinessInput(
                serviceStates: [.vm: .loaded],
                vmProcessState: .running(pid: 123)
            )),
            expectedCommandsWhenAllowed: [.removeFiles]
        )

        XCTAssertEqual(decision.commands, [])
        XCTAssertEqual(decision.state, .serviceStopBlocked)
        XCTAssertTrue(decision.blockers.contains("launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm"))
        XCTAssertTrue(decision.blockers.contains("vm-process-running:pid=123"))
    }

    func testUnexpectedCommandsFailExplicitly() throws {
        let useCase = UninstallRuntimeUseCase()
        let decision = RuntimeUninstallTransitionDecision(
            state: .started,
            persistedState: .started,
            commands: [.stopRuntimeServices],
            blockers: [],
            message: "unexpected"
        )

        XCTAssertThrowsError(try useCase.requireCommands([], in: decision)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "unexpected uninstall workflow commands state=started expected=[] actual=[Domain.RuntimeUninstallWorkflowCommand.stopRuntimeServices]"
            )
        }
    }
}
