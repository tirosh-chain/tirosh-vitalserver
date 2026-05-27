import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeProcessMessageFormatterTests: XCTestCase {
    private let formatter = RuntimeProcessMessageFormatter()

    func testReturnsTitleWhenProcessSummaryIsEmpty() {
        let result = RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")

        XCTAssertEqual(formatter.message(title: "Completed", result: result), "Completed")
    }

    func testReturnsTitleWhenProcessSummaryIsDone() {
        let result = RuntimeCommandResult(exitCode: 0, stdout: AppConstants.StatusText.done, stderr: "")

        XCTAssertEqual(formatter.message(title: "Completed", result: result), "Completed")
    }

    func testSummaryDefaultsToDoneForSilentSuccess() {
        let result = RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")

        XCTAssertEqual(formatter.summary(result), AppConstants.StatusText.done)
    }

    func testSummaryDefaultsToExitCodeForSilentFailure() {
        let result = RuntimeCommandResult(exitCode: 2, stdout: "", stderr: "")

        XCTAssertEqual(formatter.summary(result), AppConstants.StatusText.commandFailed(exitCode: 2))
    }

    func testAppendsTrimmedProcessSummary() {
        let result = RuntimeCommandResult(exitCode: 0, stdout: " updated service \n", stderr: "")

        XCTAssertEqual(
            formatter.message(title: "Completed", result: result),
            "Completed\n\nupdated service"
        )
    }

    func testUsesErrorSummaryWhenStdoutIsEmpty() {
        let result = RuntimeCommandResult(exitCode: 1, stdout: "", stderr: "failed\n")

        XCTAssertEqual(
            formatter.message(title: "Command failed", result: result),
            "Command failed\n\nfailed"
        )
    }

    func testDoesNotDuplicateTitleWhenProcessOutputStartsWithSameTitle() {
        let result = RuntimeCommandResult(
            exitCode: 0,
            stdout: "Redis backup completed.\narchive: /backups/redis.tar.gz\n",
            stderr: ""
        )

        XCTAssertEqual(
            formatter.message(title: "Redis backup completed.", result: result),
            "Redis backup completed.\narchive: /backups/redis.tar.gz"
        )
    }
}
