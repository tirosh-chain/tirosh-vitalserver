import Contracts
import OutboundAdapters
import XCTest
import Errors

final class SystemRuntimeCommandRunnerTests: XCTestCase {
    func testRunPreservesInvalidUTF8OutputAsIssues() {
        let result = SystemRuntimeCommandRunner().run(
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

    func testRunWritingOutputPreservesInvalidUTF8StderrAsIssue() {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("system-runtime-command-runner-test.out")
        defer {
            try? FileManager.default.removeItem(at: output)
        }

        let result = SystemRuntimeCommandRunner().runWritingOutput(
            "/bin/sh",
            arguments: ["-c", "printf 'ok'; printf '\\376' >&2"],
            output: output
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
        XCTAssertNil(result.executionIssue)
        XCTAssertEqual(result.outputIssues, [
            RuntimeCommandOutputIssue(
                stream: .stderr,
                message: "command stderr is not valid UTF-8"
            ),
        ])
        XCTAssertEqual(try? String(contentsOf: output, encoding: .utf8), "ok")
    }

    func testRunPreservesProcessLaunchFailureAsExecutionIssue() {
        let result = SystemRuntimeCommandRunner().run(
            "/missing/runtime-command",
            arguments: []
        )

        XCTAssertEqual(result.exitCode, 127)
        XCTAssertEqual(result.executionIssue?.kind, .processLaunchFailed)
        XCTAssertFalse(result.executionIssue?.message.isEmpty ?? true)
    }

    func testRunWritingOutputPreservesOutputPreparationFailureAsExecutionIssue() {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-system-runtime-command-runner-dir")
            .appendingPathComponent("out.txt")

        let result = SystemRuntimeCommandRunner().runWritingOutput(
            "/bin/sh",
            arguments: ["-c", "printf ok"],
            output: output
        )

        XCTAssertEqual(result.exitCode, 127)
        XCTAssertEqual(result.executionIssue?.kind, .outputFilePreparationFailed)
        XCTAssertFalse(result.executionIssue?.message.isEmpty ?? true)
    }
}
