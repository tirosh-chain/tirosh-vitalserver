import Contracts
import Domain
import XCTest

final class RuntimeVMLifecycleProcessExitPolicyTests: XCTestCase {
    private let policy = RuntimeVMLifecycleProcessExitPolicy()

    func testStoppedLifecycleIsVerifiedWithoutMutation() {
        XCTAssertEqual(
            policy.decide(lifecycleState: .stopped, expectedProcessID: 42),
            .stoppedVerified
        )
    }

    func testExistingTerminalFailureIsPreserved() {
        XCTAssertEqual(
            policy.decide(lifecycleState: .failed, expectedProcessID: 42),
            .terminalFailurePreserved
        )
    }

    func testNonTerminalLifecycleRequiresExplicitFailureRecord() {
        XCTAssertEqual(
            policy.decide(lifecycleState: .stopping, expectedProcessID: 42),
            .recordTerminalFailure(
                message: "VM process exited without terminal lifecycle state pid=42 previousState=stopping"
            )
        )
    }

    func testUnknownLifecycleBlocksRestart() {
        XCTAssertEqual(
            policy.decide(lifecycleState: .unknown("future"), expectedProcessID: 42),
            .blocked(reason: "VM lifecycle state is unknown value=future")
        )
    }

    func testServiceStopWithoutTerminalLifecycleRequiresExplicitFailureRecord() {
        XCTAssertEqual(
            RuntimeVMLifecycleProcessExitPolicy().decideAfterServiceStop(
                lifecycleState: .stopping
            ),
            .recordTerminalFailure(
                message: "VM service stopped without terminal lifecycle state previousState=stopping"
            )
        )
    }
}
