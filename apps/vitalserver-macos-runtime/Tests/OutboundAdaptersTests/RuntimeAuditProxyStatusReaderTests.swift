import Application
import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeAuditProxyStatusReaderTests: XCTestCase {
    func testReadLoadsAuditProxyStatusDocument() {
        let commandRunner = AuditProxyStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":1,"activeRecorderConnections":2,"httpRequests":3,"socketIoEventsSeen":4,"socketIoParseFailures":5,"auditWriteFailures":6,"auditFileWriteFailures":7,"auditStdoutWriteFailures":8,"redisIpWriteFailures":9}"#,
            stderr: ""
        )

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .loaded)
        XCTAssertEqual(result.httpStatus, "200")
        XCTAssertEqual(result.document?.activeWebSockets, 1)
        XCTAssertEqual(result.document?.activeRecorderConnections, 2)
        XCTAssertNil(result.readError)
        XCTAssertEqual(commandRunner.requests, [
            AuditProxyStatusCommandRequest(
                executable: "/usr/bin/curl",
                arguments: ["-fsS", "--max-time", "5", "http://127.0.0.1:8080/__audit/status"]
            ),
        ])
    }

    func testReadReportsCommandFailureWithoutInventingDocument() {
        let commandRunner = AuditProxyStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 7, stdout: "", stderr: "connection refused")

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .commandFailed)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.failed)
        XCTAssertNil(result.document)
        XCTAssertTrue(result.readError?.hasPrefix("command-failed-7 ") == true)
        XCTAssertTrue(result.readError?.contains("connection refused") == true)
    }

    func testReadReportsInvalidResponseWithoutInventingEmptyDocument() {
        let commandRunner = AuditProxyStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "{invalid-json", stderr: "")

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .invalidResponse)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertNil(result.document)
        XCTAssertTrue(result.readError?.hasPrefix("decode-failed reason=") == true)
    }

    func testReadReportsEmptyResponseDistinctFromDecodeFailure() {
        let commandRunner = AuditProxyStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "\n", stderr: "")

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .emptyResponse)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertNil(result.document)
        XCTAssertEqual(result.readError, "empty-response")
    }

    func testReadReportsInvalidCommandOutputBeforeDecoding() {
        let commandRunner = AuditProxyStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":1}"#,
            stderr: "",
            outputIssues: [
                RuntimeCommandOutputIssue(stream: .stdout, message: "stdout invalid utf8"),
            ]
        )

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .outputInvalid)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertNil(result.document)
        XCTAssertTrue(result.readError?.hasPrefix("output-invalid ") == true)
    }

    private func makeReader(commandRunner: AuditProxyStatusCommandRunner) -> RuntimeAuditProxyStatusReader {
        RuntimeAuditProxyStatusReader(
            curlPath: "/usr/bin/curl",
            commandRunner: commandRunner,
            statusURL: { port in "http://127.0.0.1:\(port)/__audit/status" }
        )
    }
}

private struct AuditProxyStatusCommandRequest: Equatable {
    let executable: String
    let arguments: [String]
}

private final class AuditProxyStatusCommandRunner: RuntimeCommandRunner {
    var result = RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    var requests: [AuditProxyStatusCommandRequest] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        requests.append(AuditProxyStatusCommandRequest(executable: executable, arguments: arguments))
        return result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}
