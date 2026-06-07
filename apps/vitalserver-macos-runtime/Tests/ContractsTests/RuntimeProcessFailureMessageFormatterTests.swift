import Contracts
import XCTest

final class RuntimeProcessFailureMessageFormatterTests: XCTestCase {
    func testProcessResultMessageIncludesExitAndStderr() {
        let result = RuntimeProcessResult(exitCode: 2, stdout: "", stderr: " denied\n")

        XCTAssertEqual(
            RuntimeProcessFailureMessageFormatter.message(result),
            "exitCode=2 stderr=denied"
        )
    }

    func testFieldBasedMessageUsesSameFailureFormatAsProcessResult() {
        let processResult = RuntimeProcessResult(
            exitCode: 127,
            stdout: "",
            stderr: "",
            outputIssues: [
                RuntimeCommandOutputIssue(stream: .stderr, message: "stderr decode failed"),
            ],
            executionIssue: RuntimeProcessExecutionIssue(
                kind: .processLaunchFailed,
                message: "launch denied"
            )
        )

        XCTAssertEqual(
            RuntimeProcessFailureMessageFormatter.message(
                exitCode: processResult.exitCode,
                stdout: processResult.stdout,
                stderr: processResult.stderr,
                outputIssues: processResult.outputIssues,
                executionIssue: processResult.executionIssue
            ),
            RuntimeProcessFailureMessageFormatter.message(processResult)
        )
        XCTAssertEqual(
            RuntimeProcessFailureMessageFormatter.message(
                exitCode: processResult.exitCode,
                stdout: processResult.stdout,
                stderr: processResult.stderr,
                outputIssues: processResult.outputIssues,
                executionIssue: processResult.executionIssue
            ),
            "exitCode=127 executionIssue=processLaunchFailed: launch denied"
        )
    }
}
