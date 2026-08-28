import Application
import Contracts
@testable import MacPlatformAgent
import RuntimeControl
import XCTest

final class PlatformAgentVerificationPersistFailureMappingTests: XCTestCase {
    func testPersistFailureBeforeSpawnIsNotChildProcessLaunchFailure() {
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: InvokePlatformAgentUpdateBootstrapVerificationError
                    .evidencePersistFailed(reason: "EACCES"),
                spawned: nil
            )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.executionIssue)
        XCTAssertTrue(
            result.stderr.contains(
                "platform-agent verification evidence persist failed"
            )
        )
    }

    func testChildSuccessPlusFinalPersistFailureMakesOuterVerifyFail() {
        let spawned = RuntimeCommandResult(
            exitCode: 0,
            stdout: "update bootstrap verified",
            stderr: "",
            executionIssue: nil
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: InvokePlatformAgentUpdateBootstrapVerificationError
                    .evidencePersistFailed(reason: "EACCES"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "update bootstrap verified")
        XCTAssertEqual(result.stderr, "")
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertTrue(
            result.outputIssues[0].message.contains(
                "platform-agent verification evidence persist failed"
            )
        )
        XCTAssertTrue(result.outputIssues[0].message.contains("EACCES"))
    }

    func testChildFailurePlusPersistFailureKeepsChildFailureAndReportsPersist() {
        let spawned = RuntimeCommandResult(
            exitCode: 2,
            stdout: "",
            stderr: "bad signature",
            executionIssue: nil
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: InvokePlatformAgentUpdateBootstrapVerificationError
                    .evidencePersistFailed(reason: "EACCES"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stderr, "bad signature")
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertTrue(
            result.outputIssues[0].message.contains(
                "platform-agent verification evidence persist failed"
            )
        )
    }

    func testActualSpawnFailureRemainsOnTheChildProcessResult() {
        let spawned = RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "launcher missing",
            executionIssue: RuntimeProcessExecutionIssue(
                kind: .processLaunchFailed,
                message: "launcher missing"
            )
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: InvokePlatformAgentUpdateBootstrapVerificationError
                    .evidencePersistFailed(reason: "EACCES"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.executionIssue?.kind, .processLaunchFailed)
        XCTAssertEqual(result.executionIssue?.message, "launcher missing")
        XCTAssertEqual(result.outputIssues.count, 1)
    }

    func testSelectionPersistFailureAfterChildSuccessMakesOuterVerifyFail() {
        let spawned = RuntimeCommandResult(
            exitCode: 0,
            stdout: "update bootstrap verified",
            stderr: "",
            executionIssue: nil
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                    .persistFailed(reason: "EACCES"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertTrue(
            result.outputIssues[0].message.contains(
                "platform-agent verified selection persist failed"
            )
        )
    }

    func testSelectionInFlightAfterChildSuccessMakesOuterVerifyFail() {
        let spawned = RuntimeCommandResult(
            exitCode: 0,
            stdout: "update bootstrap verified",
            stderr: "",
            executionIssue: nil
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                    .inFlight(requestId: "request-1"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "update bootstrap verified")
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertTrue(
            result.outputIssues[0].message.contains(
                "platform-agent verified selection in flight requestId=request-1"
            )
        )
        XCTAssertFalse(
            result.outputIssues[0].message.contains("persist failed")
        )
    }

    func testSelectionDecodeFailureAfterChildSuccessMakesOuterVerifyFail() {
        let spawned = RuntimeCommandResult(
            exitCode: 0,
            stdout: "update bootstrap verified",
            stderr: "",
            executionIssue: nil
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                    .decodeFailed(path: "/tmp/current.json", reason: "not json"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertTrue(
            result.outputIssues[0].message.contains(
                "platform-agent verified selection decode failed"
            )
        )
        XCTAssertTrue(result.outputIssues[0].message.contains("/tmp/current.json"))
        XCTAssertFalse(
            result.outputIssues[0].message.contains("persist failed")
        )
    }

    func testChildNonzeroPlusSelectionInFlightKeepsChildExitCode() {
        let spawned = RuntimeCommandResult(
            exitCode: 2,
            stdout: "",
            stderr: "bad signature",
            executionIssue: nil
        )
        let result = PlatformAgentVerificationPersistFailureMapping
            .commandResult(
                error: RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                    .inFlight(requestId: "request-1"),
                spawned: spawned
            )

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stderr, "bad signature")
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertTrue(
            result.outputIssues[0].message.contains(
                "in flight requestId=request-1"
            )
        )
    }
}
