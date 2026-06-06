import RuntimeControl
@testable import OutboundAdapters
import XCTest
import Errors
@testable import InboundAdapters

final class ProcessRunnerTests: XCTestCase {
    func testRunSyncReportsInvalidUTF8OutputIssues() {
        let result = ProcessRunner.runSync(
            "/bin/sh",
            arguments: ["-c", "printf '\\377'; printf '\\376' >&2"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
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
}
