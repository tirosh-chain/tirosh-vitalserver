import Application
import Contracts
import Domain
import Workflow
import XCTest

final class UpdateHandoffSupervisorWorkflowTests: XCTestCase {
    func testQueuedJobIsDurablyClaimedBeforeChildOwnerLaunch() throws {
        let harness = SupervisorHarness()

        let output = try UpdateHandoffSupervisorWorkflow().reconcile(
            harness.queued,
            operations: harness.operations()
        )

        XCTAssertEqual(output.state, .launching)
        XCTAssertEqual(harness.events, [
            "save:launching:1",
            "launch:launch-1",
        ])
    }

    func testRestartRecoversLaunchingJobFromChildStartReceipt() throws {
        let harness = SupervisorHarness()
        let launching = try harness.launching()
        harness.startReceipt = .loaded(
            UpdateHandoffChildStartReceipt(
                jobId: launching.jobId,
                child: harness.child
            )
        )

        let output = try UpdateHandoffSupervisorWorkflow().reconcile(
            launching,
            operations: harness.operations()
        )

        XCTAssertEqual(output.state, .running)
        XCTAssertEqual(output.child, harness.child)
        XCTAssertEqual(harness.events, [
            "read-start",
            "save:running:2",
            "read-completion",
            "observe",
        ])
    }

    func testCompletionReceiptSettlesRestartedRunningJob() throws {
        let harness = SupervisorHarness()
        let running = try harness.running()
        harness.completionReceipt = .loaded(
            harness.completion(exitCode: 0)
        )

        let output = try UpdateHandoffSupervisorWorkflow().reconcile(
            running,
            operations: harness.operations()
        )

        XCTAssertEqual(output.state, .succeeded)
        XCTAssertEqual(harness.events, [
            "read-completion",
            "save:succeeded:3",
        ])
    }

    func testPidAbsenceWithoutReceiptBecomesInterruptedNotSucceeded() throws {
        let harness = SupervisorHarness()
        let running = try harness.running()
        harness.observation = .notRunning(harness.child)

        let output = try UpdateHandoffSupervisorWorkflow().reconcile(
            running,
            operations: harness.operations()
        )

        XCTAssertEqual(output.state, .interrupted)
        XCTAssertEqual(output.completion?.outcome, .interrupted)
        XCTAssertNil(output.completion?.exitCode)
    }

    func testCancellationDoesNotSettleUntilProcessTreeTerminationSucceeds() throws {
        let harness = SupervisorHarness()
        let requested = try UpdateHandoffJobStateMachine.transition(
            try harness.running(),
            event: .cancellationRequested(
                observedAt: "2026-07-29T00:03:00Z"
            )
        )
        harness.termination = .failed(
            harness.child,
            reason: "permission denied"
        )

        XCTAssertThrowsError(try UpdateHandoffSupervisorWorkflow().reconcile(
            requested,
            operations: harness.operations()
        )) { error in
            XCTAssertEqual(
                error as? UpdateHandoffSupervisorWorkflowError,
                .processTreeTerminationFailed(
                    jobId: "job-1",
                    reason: "permission denied"
                )
            )
        }
        XCTAssertFalse(harness.events.contains { $0.contains("interrupted") })
    }

    func testWaitTimeoutPreservesNonterminalState() {
        let harness = SupervisorHarness()

        XCTAssertThrowsError(try UpdateHandoffSupervisorWorkflow().wait(
            jobId: "job-1",
            attempts: 2,
            load: { harness.queued },
            pause: {}
        )) { error in
            XCTAssertEqual(
                error as? UpdateHandoffSupervisorWorkflowError,
                .waitTimedOut(jobId: "job-1", state: .queued)
            )
        }
    }
}

private final class SupervisorHarness {
    var events: [String] = []
    var startReceipt:
        UpdateHandoffReceiptReadResult<UpdateHandoffChildStartReceipt> =
            .missing(path: "/jobs/job-1/child-start.json")
    var completionReceipt:
        UpdateHandoffReceiptReadResult<
            UpdateHandoffChildCompletionReceipt
        > = .missing(path: "/jobs/job-1/child-completion.json")
    lazy var observation: UpdateHandoffChildObservation = .running(child)
    lazy var termination: UpdateHandoffProcessTreeTerminationResult =
        .terminated(child)

    let child = UpdateHandoffChildIdentity(
        launchId: "launch-1",
        processId: 101,
        processGroupId: 101,
        startedAt: "2026-07-29T00:02:00Z"
    )

    var queued: UpdateHandoffJobDocument {
        UpdateHandoffJobStateMachine.enqueue(
            jobId: "job-1",
            updateId: "update-1",
            operationId: "operation-1",
            invocationPath: "/updates/update-1/invocation.json",
            updaterPath: "/updates/update-1/updater",
            observedAt: "2026-07-29T00:00:00Z"
        )
    }

    func launching() throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            queued,
            event: .launchClaimed(
                launchId: "launch-1",
                observedAt: "2026-07-29T00:01:00Z"
            )
        )
    }

    func running() throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            try launching(),
            event: .childStarted(
                child,
                observedAt: "2026-07-29T00:02:00Z"
            )
        )
    }

    func completion(exitCode: Int32) -> UpdateHandoffChildCompletionReceipt {
        UpdateHandoffChildCompletionReceipt(
            jobId: "job-1",
            launchId: child.launchId,
            processId: child.processId,
            processGroupId: child.processGroupId,
            exitCode: exitCode,
            launchFailureReason: nil,
            finishedAt: "2026-07-29T00:04:00Z"
        )
    }

    func operations() -> UpdateHandoffSupervisorWorkflowOperations {
        let manager = ManageUpdateHandoffJobUseCase()
        return UpdateHandoffSupervisorWorkflowOperations(
            enqueue: manager.enqueue,
            launchClaimed: manager.launchClaimed,
            childStarted: manager.childStarted,
            childCompleted: manager.childCompleted,
            cancellationRequested: manager.cancellationRequested,
            processTreeTerminated: manager.processTreeTerminated,
            childCompletionUnavailable:
                manager.childCompletionUnavailable,
            save: { [self] job, expected in
                events.append("save:\(job.state.rawValue):\(expected.map(String.init) ?? "nil")")
            },
            launchChildOwner: { [self] job in
                events.append("launch:\(job.launchId ?? "missing")")
            },
            readStartReceipt: { [self] _ in
                events.append("read-start")
                return startReceipt
            },
            readCompletionReceipt: { [self] _ in
                events.append("read-completion")
                return completionReceipt
            },
            observeChild: { [self] _ in
                events.append("observe")
                return observation
            },
            terminateProcessTree: { [self] _ in
                events.append("terminate")
                return termination
            },
            makeId: { "launch-1" },
            now: { "2026-07-29T00:05:00Z" },
            describeFailure: { String(describing: $0) }
        )
    }
}
