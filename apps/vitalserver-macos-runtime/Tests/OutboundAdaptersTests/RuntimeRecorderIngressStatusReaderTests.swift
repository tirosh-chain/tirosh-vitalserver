import Application
import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeRecorderIngressStatusReaderTests: XCTestCase {
    func testReadLoadsRecorderIngressStatusDocument() {
        let commandRunner = RecorderIngressStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":1,"activeRecorderConnections":2,"httpRequests":3,"socketIoEventsSeen":4,"socketIoParseFailures":5,"auditWriteFailures":6,"auditFileWriteFailures":7,"auditStdoutWriteFailures":8,"failureLogWriteFailures":9,"redisIpWriteFailures":10,"rawArchive":{"status":"ready","persistedEvents":11,"persistedBytes":4096,"writeFailures":0,"lastArchiveId":"send-data-raw.jsonl","lastOffset":128,"autoExport":{"status":"running","finalizable":true,"reasons":["inactive"],"archivePath":"/var/lib/vital/recorder-ingress/send-data-raw.jsonl","archiveCursor":128,"cursorStableForMs":5000,"lastDecisionAt":"2026-06-01T00:00:00Z","activeJob":{"jobId":"job-1","archivePath":"/var/lib/vital/recorder-ingress/send-data-raw.jsonl","archiveCursor":128,"state":"running","attempts":1,"maxAttempts":3,"createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-06-01T00:00:01Z","startedAt":"2026-06-01T00:00:01Z"},"uploadedJobs":2,"failedJobs":1,"lastResult":{"uploadStatus":"uploaded","uploadResult":{"fileId":"vital-1"},"bytes":4096,"ok":true},"lastFailure":{"reason":"upload_failed","message":"timeout","occurredAt":"2026-06-01T00:00:02Z"}}},"spool":{"mode":"spool_and_replay","status":"ready","skippedRealtimeEvents":4,"pendingItems":10,"pendingBytes":2048},"replay":{"status":"replaying","inFlightItems":1,"replayLagSeconds":12}}"#,
            stderr: ""
        )

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .loaded)
        XCTAssertEqual(result.httpStatus, "200")
        XCTAssertEqual(result.document?.activeWebSockets, 1)
        XCTAssertEqual(result.document?.activeRecorderConnections, 2)
        XCTAssertEqual(result.document?.failureLogWriteFailures, 9)
        XCTAssertEqual(result.document?.rawArchive?.status, "ready")
        XCTAssertEqual(result.document?.rawArchive?.persistedEvents, 11)
        XCTAssertEqual(result.document?.rawArchive?.persistedBytes, 4096)
        XCTAssertEqual(result.document?.rawArchive?.lastOffset, 128)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.status, "running")
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.finalizable, true)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.reasons, ["inactive"])
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.archiveCursor, 128)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.cursorStableForMs, 5000)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.activeJob?.jobId, "job-1")
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.activeJob?.attempts, 1)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.uploadedJobs, 2)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.failedJobs, 1)
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.lastResult?.values["uploadStatus"], .string("uploaded"))
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.lastResult?.values["uploadResult"], .object(["fileId": .string("vital-1")]))
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.lastResult?.values["bytes"], .int(4096))
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.lastResult?.values["ok"], .bool(true))
        XCTAssertEqual(result.document?.rawArchive?.autoExport?.lastFailure?.reason, "upload_failed")
        XCTAssertEqual(result.document?.spool?.mode, "spool_and_replay")
        XCTAssertEqual(result.document?.spool?.skippedRealtimeEvents, 4)
        XCTAssertEqual(result.document?.spool?.pendingItems, 10)
        XCTAssertEqual(result.document?.replay?.status, "replaying")
        XCTAssertEqual(result.document?.replay?.replayLagSeconds, 12)
        XCTAssertNil(result.readError)
        XCTAssertEqual(commandRunner.requests, [
            RecorderIngressStatusCommandRequest(
                executable: "/usr/bin/curl",
                arguments: ["-fsS", "--max-time", "5", "http://127.0.0.1:8080/recorder-ingress/status"]
            ),
        ])
    }

    func testReadReportsCommandFailureWithoutInventingDocument() {
        let commandRunner = RecorderIngressStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 7, stdout: "", stderr: "connection refused")

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .commandFailed)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.failed)
        XCTAssertNil(result.document)
        XCTAssertTrue(result.readError?.hasPrefix("command-failed-7 ") == true)
        XCTAssertTrue(result.readError?.contains("connection refused") == true)
    }

    func testReadReportsInvalidResponseWithoutInventingEmptyDocument() {
        let commandRunner = RecorderIngressStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "{invalid-json", stderr: "")

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .invalidResponse)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertNil(result.document)
        XCTAssertTrue(result.readError?.hasPrefix("decode-failed reason=") == true)
    }

    func testReadReportsEmptyResponseDistinctFromDecodeFailure() {
        let commandRunner = RecorderIngressStatusCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "\n", stderr: "")

        let result = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(result.readState, .emptyResponse)
        XCTAssertEqual(result.httpStatus, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertNil(result.document)
        XCTAssertEqual(result.readError, "empty-response")
    }

    func testReadReportsInvalidCommandOutputBeforeDecoding() {
        let commandRunner = RecorderIngressStatusCommandRunner()
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

    private func makeReader(commandRunner: RecorderIngressStatusCommandRunner) -> RuntimeRecorderIngressStatusReader {
        RuntimeRecorderIngressStatusReader(
            curlPath: "/usr/bin/curl",
            commandRunner: commandRunner,
            statusURL: { port in "http://127.0.0.1:\(port)/recorder-ingress/status" }
        )
    }
}

private struct RecorderIngressStatusCommandRequest: Equatable {
    let executable: String
    let arguments: [String]
}

private final class RecorderIngressStatusCommandRunner: RuntimeCommandRunner {
    var result = RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    var requests: [RecorderIngressStatusCommandRequest] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        requests.append(RecorderIngressStatusCommandRequest(executable: executable, arguments: arguments))
        return result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}
