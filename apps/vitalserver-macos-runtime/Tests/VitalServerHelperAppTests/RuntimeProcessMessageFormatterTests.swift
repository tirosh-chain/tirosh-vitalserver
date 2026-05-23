import RuntimeControl
@testable import VitalServerHelperApp
import XCTest

final class RuntimeProcessMessageFormatterTests: XCTestCase {
    private let formatter = RuntimeProcessMessageFormatter()

    func testReturnsTitleWhenProcessSummaryIsEmpty() {
        let result = ProcessResult(exitCode: 0, stdout: "", stderr: "")

        XCTAssertEqual(formatter.message(title: "Completed", result: result), "Completed")
    }

    func testReturnsTitleWhenProcessSummaryIsDone() {
        let result = ProcessResult(exitCode: 0, stdout: AppConstants.StatusText.done, stderr: "")

        XCTAssertEqual(formatter.message(title: "Completed", result: result), "Completed")
    }

    func testAppendsTrimmedProcessSummary() {
        let result = ProcessResult(exitCode: 0, stdout: " updated service \n", stderr: "")

        XCTAssertEqual(
            formatter.message(title: "Completed", result: result),
            "Completed\n\nupdated service"
        )
    }

    func testUsesErrorSummaryWhenStdoutIsEmpty() {
        let result = ProcessResult(exitCode: 1, stdout: "", stderr: "failed\n")

        XCTAssertEqual(
            formatter.message(title: "Command failed", result: result),
            "Command failed\n\nfailed"
        )
    }
}
