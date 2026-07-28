import Contracts
import Domain
import XCTest

final class UpdateHandoffJobStateMachineTests: XCTestCase {
    func testOwnsExplicitChildIdentityFromClaimThroughCompletion() throws {
        let queued = job()
        let launching = try UpdateHandoffJobStateMachine.transition(
            queued,
            event: .launchClaimed(
                launchId: "launch-1",
                observedAt: "2026-07-29T00:01:00Z"
            )
        )
        let child = UpdateHandoffChildIdentity(
            launchId: "launch-1",
            processId: 101,
            processGroupId: 101,
            startedAt: "2026-07-29T00:02:00Z"
        )
        let running = try UpdateHandoffJobStateMachine.transition(
            launching,
            event: .childStarted(
                child,
                observedAt: "2026-07-29T00:02:00Z"
            )
        )
        let completed = try UpdateHandoffJobStateMachine.transition(
            running,
            event: .childCompleted(
                receipt(child: child, exitCode: 0),
                observedAt: "2026-07-29T00:03:00Z"
            )
        )

        XCTAssertEqual(launching.state, .launching)
        XCTAssertEqual(running.child, child)
        XCTAssertEqual(completed.state, .succeeded)
        XCTAssertEqual(completed.completion?.outcome, .succeeded)
        XCTAssertEqual(completed.revision, 4)
    }

    func testMissingChildCompletionIsInterruptedAndNeverSucceeded() throws {
        let running = try runningJob()
        let interrupted = try UpdateHandoffJobStateMachine.transition(
            running,
            event: .childCompletionUnavailable(
                reason: "child absent without receipt",
                observedAt: "2026-07-29T00:04:00Z"
            )
        )

        XCTAssertEqual(interrupted.state, .interrupted)
        XCTAssertEqual(interrupted.completion?.outcome, .interrupted)
        XCTAssertNil(interrupted.completion?.exitCode)
    }

    func testCompletionMustMatchOwnedChildIdentity() throws {
        let running = try runningJob()
        let other = UpdateHandoffChildIdentity(
            launchId: "other-launch",
            processId: 101,
            processGroupId: 101,
            startedAt: "2026-07-29T00:02:00Z"
        )

        XCTAssertThrowsError(try UpdateHandoffJobStateMachine.transition(
            running,
            event: .childCompleted(
                receipt(child: other, exitCode: 0),
                observedAt: "2026-07-29T00:03:00Z"
            )
        )) { error in
            XCTAssertEqual(
                error as? UpdateHandoffJobTransitionError,
                .invalidCompletionReceipt
            )
        }
    }

    private func runningJob() throws -> UpdateHandoffJobDocument {
        let launching = try UpdateHandoffJobStateMachine.transition(
            job(),
            event: .launchClaimed(
                launchId: "launch-1",
                observedAt: "2026-07-29T00:01:00Z"
            )
        )
        return try UpdateHandoffJobStateMachine.transition(
            launching,
            event: .childStarted(
                UpdateHandoffChildIdentity(
                    launchId: "launch-1",
                    processId: 101,
                    processGroupId: 101,
                    startedAt: "2026-07-29T00:02:00Z"
                ),
                observedAt: "2026-07-29T00:02:00Z"
            )
        )
    }

    private func job() -> UpdateHandoffJobDocument {
        UpdateHandoffJobStateMachine.enqueue(
            jobId: "job-1",
            updateId: "update-1",
            operationId: "operation-1",
            invocationPath: "/updates/update-1/invocation.json",
            updaterPath: "/updates/update-1/updater",
            observedAt: "2026-07-29T00:00:00Z"
        )
    }

    private func receipt(
        child: UpdateHandoffChildIdentity,
        exitCode: Int32
    ) -> UpdateHandoffChildCompletionReceipt {
        UpdateHandoffChildCompletionReceipt(
            jobId: "job-1",
            launchId: child.launchId,
            processId: child.processId,
            processGroupId: child.processGroupId,
            exitCode: exitCode,
            launchFailureReason: nil,
            finishedAt: "2026-07-29T00:03:00Z"
        )
    }
}
