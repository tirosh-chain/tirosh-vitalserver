import Contracts
import Workflow
import XCTest

final class RuntimeGuestShutdownRunnerTests: XCTestCase {
    func testPrepareWritesRequestAndWaitsForReadyResult() throws {
        let events = EventLog()
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "stopping")),
            .loaded(result(
                status: .ready,
                requestId: "request-1",
                message: "poweroff requested",
                shutdownPhase: .poweroffRequested
            )),
        ]
        let runner = makeRunner(
            events: events,
            loadResult: { results.removeFirst() }
        )

        try runner.prepareForUpdate(version: "1.2.3")

        XCTAssertEqual(events.values, [
            "log:guest update shutdown requested version=1.2.3",
            "capability",
            "mkdir",
            "remove-result",
            "write-request:request-1:2026-05-22T00:00:00Z:1.2.3",
            "log:waiting for guest update shutdown result timeoutSeconds=300.0",
            "log:waiting for guest update shutdown worker",
            "progress:waiting for guest update shutdown worker",
            "sleep",
            "sleep",
            "log:guest update shutdown result ready message=poweroff requested",
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

        XCTAssertThrowsError(try runner.prepareForUpdate(version: "1.2.3")) { error in
            XCTAssertEqual(String(describing: error), "backup failed")
        }
        XCTAssertTrue(events.values.contains("log:guest update shutdown result failed message=backup failed"))
    }

    func testPrepareStopsBeforeWritingRequestWhenCapabilityIsMissing() {
        let events = EventLog()
        let runner = makeRunner(
            events: events,
            requireCapability: {
                throw RuntimeGuestShutdownWorkflowError.operationFailed("guest capability missing: prepare-update-shutdown")
            },
            loadResult: { .missing }
        )

        XCTAssertThrowsError(try runner.prepareForUpdate(version: "1.2.3")) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
        XCTAssertEqual(events.values, [
            "log:guest update shutdown requested version=1.2.3",
            "capability",
        ])
    }

    private func makeRunner(
        events: EventLog,
        requireCapability: @escaping () throws -> Void = {},
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    ) -> RuntimeGuestShutdownRunner {
        RuntimeGuestShutdownRunner(
            requireCapability: {
                events.append("capability")
                try requireCapability()
            },
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
            },
            waitTimeoutSeconds: 300
        )
    }

    private func result(
        status: GuestShutdownStatus,
        requestId: String,
        message: String,
        shutdownPhase: GuestShutdownPhase? = nil
    ) -> GuestUpdateShutdownResultDocument {
        GuestUpdateShutdownResultDocument(
            schemaVersion: 1,
            requestId: requestId,
            operation: .prepareUpdateShutdown,
            status: status,
            shutdownPhase: shutdownPhase,
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
