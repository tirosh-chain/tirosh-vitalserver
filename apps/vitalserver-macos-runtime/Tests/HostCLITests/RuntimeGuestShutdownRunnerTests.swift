import Contracts
import Core
@testable import HostCLI
import XCTest

final class RuntimeGuestShutdownRunnerTests: XCTestCase {
    func testPrepareWritesRequestAndWaitsForReadyResult() throws {
        let events = EventLog()
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "stopping")),
            .loaded(result(status: .ready, requestId: "request-1", message: "ready")),
        ]
        let runner = makeRunner(
            events: events,
            loadResult: { results.removeFirst() }
        )

        try runner.prepareForUpdate(version: "1.2.3")

        XCTAssertEqual(events.values, [
            "log:guest update shutdown requested version=1.2.3",
            "mkdir",
            "remove-result",
            "write-request:request-1:2026-05-22T00:00:00Z:1.2.3",
            "log:waiting for guest update shutdown result timeoutSeconds=300.0",
            "log:waiting for guest update shutdown worker",
            "progress:waiting for guest update shutdown worker",
            "sleep",
            "sleep",
            "log:guest update shutdown result ready message=ready",
            "log:guest update shutdown ready version=1.2.3",
        ])
    }

    func testPrepareFailsWhenGuestReportsFailure() {
        let events = EventLog()
        let runner = makeRunner(
            events: events,
            loadResult: {
                .loaded(self.result(status: .failed, requestId: "request-1", message: "backup failed"))
            }
        )

        XCTAssertThrowsError(try runner.prepareForUpdate(version: "1.2.3"))
        XCTAssertTrue(events.values.contains("log:guest update shutdown result failed message=backup failed"))
    }

    private func makeRunner(
        events: EventLog,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    ) -> RuntimeGuestShutdownRunner {
        RuntimeGuestShutdownRunner(
            createRunDirectory: {
                events.append("mkdir")
            },
            removePreviousResult: {
                events.append("remove-result")
            },
            requestID: {
                "request-1"
            },
            timestamp: {
                "2026-05-22T00:00:00Z"
            },
            writeRequest: { request in
                events.append("write-request:\(request.id):\(request.requestedAt):\(request.version)")
            },
            loadResult: loadResult,
            reportProgress: { message in
                events.append("progress:\(message)")
            },
            sleep: {
                events.append("sleep")
            },
            log: { message in
                events.append("log:\(message)")
            }
        )
    }

    private func result(
        status: GuestShutdownStatus,
        requestId: String,
        message: String
    ) -> GuestUpdateShutdownResultDocument {
        GuestUpdateShutdownResultDocument(
            schemaVersion: 1,
            requestId: requestId,
            operation: .prepareUpdateShutdown,
            status: status,
            message: message,
            updatedAt: "2026-05-22T00:00:00Z"
        )
    }

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
