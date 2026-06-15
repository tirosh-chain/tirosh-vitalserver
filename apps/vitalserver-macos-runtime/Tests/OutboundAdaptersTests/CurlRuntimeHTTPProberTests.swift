import Application
import Contracts
import OutboundAdapters
import XCTest
import Errors

final class CurlRuntimeHTTPProberTests: XCTestCase {
    func testStatusCodeReturnsHTTPCodeWhenCurlSucceedsWithExplicitOutput() {
        let commandRunner = CurlProbeCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "200\n", stderr: "")

        let status = CurlRuntimeHTTPProber(commandRunner: commandRunner)
            .statusRead(url: "http://127.0.0.1/health")

        XCTAssertEqual(status, .reportedStatus("200"))
        XCTAssertEqual(status.statusText, "200")
        XCTAssertEqual(commandRunner.requests, [
            RuntimeCommandRequest(
                executable: "/usr/bin/curl",
                arguments: [
                    "-sS",
                    "-L",
                    "-o",
                    "/dev/null",
                    "-w",
                    "%{http_code}",
                    "--max-time",
                    "5",
                    "http://127.0.0.1/health",
                ]
            ),
        ])
    }

    func testStatusCodePreservesCurlCommandFailureReason() {
        let commandRunner = CurlProbeCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 7, stdout: "000", stderr: "connection refused")

        let status = CurlRuntimeHTTPProber(commandRunner: commandRunner)
            .statusRead(url: "http://127.0.0.1/health")

        XCTAssertEqual(
            status,
            .commandFailed("exitCode=7 stderr=connection refused stdout=000")
        )
        XCTAssertEqual(status.statusText, "http-probe-command-failed exitCode=7 stderr=connection refused stdout=000")
    }

    func testStatusCodePreservesInvalidOutputIssueInsteadOfReturningGenericFailed() {
        let commandRunner = CurlProbeCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 0,
            stdout: "",
            stderr: "",
            outputIssues: [
                RuntimeCommandOutputIssue(
                    stream: .stdout,
                    message: "command stdout is not valid UTF-8"
                ),
            ]
        )

        let status = CurlRuntimeHTTPProber(commandRunner: commandRunner)
            .statusRead(url: "http://127.0.0.1/health")

        XCTAssertEqual(
            status,
            .outputInvalid("exitCode=0 outputIssues=stdout:command stdout is not valid UTF-8")
        )
        XCTAssertEqual(status.statusText, "http-probe-output-invalid exitCode=0 outputIssues=stdout:command stdout is not valid UTF-8")
    }

    func testStatusCodePreservesExecutionIssueInsteadOfGenericCommandFailure() {
        let commandRunner = CurlProbeCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 127,
            stdout: "",
            stderr: "",
            executionIssue: RuntimeProcessExecutionIssue(
                kind: .processLaunchFailed,
                message: "curl denied"
            )
        )

        let status = CurlRuntimeHTTPProber(commandRunner: commandRunner)
            .statusRead(url: "http://127.0.0.1/health")

        XCTAssertEqual(
            status,
            .commandFailed("exitCode=127 executionIssue=processLaunchFailed: curl denied")
        )
        XCTAssertEqual(status.statusText, "http-probe-command-failed exitCode=127 executionIssue=processLaunchFailed: curl denied")
    }

    func testStatusCodeDistinguishesEmptyCurlOutputFromCommandFailure() {
        let commandRunner = CurlProbeCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "\n", stderr: "")

        let status = CurlRuntimeHTTPProber(commandRunner: commandRunner)
            .statusRead(url: "http://127.0.0.1/health")

        XCTAssertEqual(status, .emptyStatus)
        XCTAssertEqual(status.statusText, "http-probe-empty-status")
    }
}

private struct RuntimeCommandRequest: Equatable {
    let executable: String
    let arguments: [String]
}

private final class CurlProbeCommandRunner: RuntimeCommandRunner {
    var result = RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    var requests: [RuntimeCommandRequest] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        requests.append(RuntimeCommandRequest(executable: executable, arguments: arguments))
        return result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}
