import Contracts
import RuntimeControl
@testable import OutboundAdapters
import XCTest
import Errors
@testable import InboundAdapters

final class ProcessRunnerTests: XCTestCase {
    func testRunSyncAppliesExplicitEnvironmentWithoutDroppingProcessEnvironment() {
        let result = ProcessRunner.runSync(
            "/bin/sh",
            arguments: [
                "-c",
                "printf '%s|%s' \"$VITALSERVER_VM_HOME\" \"$PATH\"",
            ],
            environment: [
                "VITALSERVER_VM_HOME": "/Library/Application Support/VitalServerHelper/vm",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stdout.hasPrefix(
                "/Library/Application Support/VitalServerHelper/vm|/"
            )
        )
    }

    func testRunSyncReportsInvalidUTF8OutputIssues() {
        let result = ProcessRunner.runSync(
            "/bin/sh",
            arguments: ["-c", "printf '\\377'; printf '\\376' >&2"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues, [
            RuntimeCommandOutputIssue(
                stream: .stdout,
                message: "command stdout is not valid UTF-8"
            ),
            RuntimeCommandOutputIssue(
                stream: .stderr,
                message: "command stderr is not valid UTF-8"
            ),
        ])
    }

    func testRunSyncPreservesProcessLaunchFailureAsExecutionIssue() {
        let result = ProcessRunner.runSync(
            "/missing/runtime-control-command",
            arguments: []
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.executionIssue?.kind, .processLaunchFailed)
        XCTAssertFalse(result.executionIssue?.message.isEmpty ?? true)
    }
}
