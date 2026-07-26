import Contracts
import Domain
import XCTest

final class RuntimeVMLifecycleTransitionPolicyTests: XCTestCase {
    private let policy = RuntimeVMLifecycleTransitionPolicy()

    func testBeginsFirstRunOnlyWithExplicitIdentity() throws {
        let proposed = document(state: .starting)

        XCTAssertEqual(try policy.nextRevision(
            current: nil,
            currentRevision: nil,
            proposed: proposed,
            expectedRevision: nil
        ), 1)

        let invalid = RuntimeVMLifecycleDocument(
            state: .starting,
            operation: .startServices,
            operationID: "operation-1",
            bootID: nil,
            startedAt: "2026-07-14T07:00:00Z",
            updatedAt: "2026-07-14T07:00:00Z"
        )
        XCTAssertThrowsError(try policy.nextRevision(
            current: nil,
            currentRevision: nil,
            proposed: invalid,
            expectedRevision: nil
        )) { error in
            XCTAssertEqual(
                error as? RuntimeVMLifecycleTransitionError,
                .invalidField(field: "bootID", value: "missing")
            )
        }
    }

    func testTransitionsSameRunWithExpectedRevision() throws {
        let current = document(state: .starting)
        let proposed = document(
            state: .bootstrapping,
            updatedAt: "2026-07-14T07:00:01Z"
        )

        XCTAssertEqual(try policy.nextRevision(
            current: current,
            currentRevision: 4,
            proposed: proposed,
            expectedRevision: 4
        ), 5)

        XCTAssertThrowsError(try policy.nextRevision(
            current: current,
            currentRevision: 4,
            proposed: proposed,
            expectedRevision: 3
        )) { error in
            XCTAssertEqual(
                error as? RuntimeVMLifecycleTransitionError,
                .staleRevision(expected: 3, actual: 4)
            )
        }
    }

    func testRejectsRunIdentityChangeInsideTransition() {
        let current = document(state: .bootstrapping)
        let proposed = document(
            state: .running,
            bootID: "boot-2",
            updatedAt: "2026-07-14T07:00:02Z"
        )

        XCTAssertThrowsError(try policy.nextRevision(
            current: current,
            currentRevision: 2,
            proposed: proposed,
            expectedRevision: 2
        )) { error in
            XCTAssertEqual(
                error as? RuntimeVMLifecycleTransitionError,
                .runIDMismatch(expected: "boot-1", actual: "boot-2")
            )
        }
    }

    func testNewRunRequiresTerminalPriorStateAndNewBootID() throws {
        let running = document(state: .running)
        let next = document(
            state: .starting,
            operationID: "operation-2",
            bootID: "boot-2",
            startedAt: "2026-07-14T08:00:00Z",
            updatedAt: "2026-07-14T08:00:00Z"
        )
        XCTAssertThrowsError(try policy.nextRevision(
            current: running,
            currentRevision: 3,
            proposed: next,
            expectedRevision: 3
        ))

        let stopped = document(
            state: .stopped,
            updatedAt: "2026-07-14T07:30:00Z"
        )
        XCTAssertEqual(try policy.nextRevision(
            current: stopped,
            currentRevision: 4,
            proposed: next,
            expectedRevision: 4
        ), 5)
    }

    private func document(
        state: RuntimeVMLifecycleState,
        operationID: String = "operation-1",
        bootID: String = "boot-1",
        startedAt: String = "2026-07-14T07:00:00Z",
        updatedAt: String = "2026-07-14T07:00:00Z"
    ) -> RuntimeVMLifecycleDocument {
        RuntimeVMLifecycleDocument(
            state: state,
            operation: .startServices,
            operationID: operationID,
            bootID: bootID,
            startedAt: startedAt,
            updatedAt: updatedAt,
            deadlineAt: state == .starting || state == .bootstrapping
                ? "2026-07-14T07:05:00Z"
                : nil,
            terminalReason: state == .failed ? .launchFailed : nil,
            message: "state=\(state.rawValue)"
        )
    }
}
