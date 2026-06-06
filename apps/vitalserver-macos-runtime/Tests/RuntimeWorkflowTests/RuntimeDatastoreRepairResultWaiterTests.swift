import Contracts
import Workflow
import XCTest

final class RuntimeDatastoreRepairResultWaiterTests: XCTestCase {
    func testWaitCompletesWhenGuestReportsCompleted() throws {
        let harness = DatastoreRepairResultWaitHarness(results: [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "repairing")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ])

        try harness.waiter.wait(for: RuntimeDatastoreRepairRequest(
            id: "request-1",
            requestedAt: "2026-05-22T00:00:00Z"
        ))

        XCTAssertTrue(harness.events.contains("log:datastore repair guest result completed message=done"))
        XCTAssertTrue(harness.events.contains("sleep"))
    }

    func testWaitReportsProgressAndThrowsWhenGuestFails() {
        let harness = DatastoreRepairResultWaitHarness(results: [
            .missing,
            .loaded(result(status: .failed, requestId: "request-1", message: "repair failed")),
        ])

        XCTAssertThrowsError(try harness.waiter.wait(for: RuntimeDatastoreRepairRequest(
            id: "request-1",
            requestedAt: "2026-05-22T00:00:00Z"
        ))) { error in
            XCTAssertEqual(String(describing: error), "runtime health check failed")
        }
        XCTAssertTrue(harness.events.contains("status:recovering:repair-datastore:waiting for datastore repair guest worker"))
        XCTAssertTrue(harness.events.contains("log:datastore repair guest result failed message=repair failed"))
    }
}

private final class DatastoreRepairResultWaitHarness {
    var results: [RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>]
    var events: [String] = []

    init(results: [RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>]) {
        self.results = results
    }

    var waiter: RuntimeDatastoreRepairResultWaiter {
        RuntimeDatastoreRepairResultWaiter(
            loadResult: {
                if self.results.count > 1 {
                    return self.results.removeFirst()
                }
                return self.results[0]
            },
            writeStatus: { status, operation, message in
                self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            sleep: {
                self.events.append("sleep")
            },
            log: { message in
                self.events.append("log:\(message)")
            },
            waitTimeoutSeconds: 300
        )
    }
}

private func result(
    status: DatastoreRepairStatus,
    requestId: String,
    message: String
) -> DatastoreRepairResultDocument {
    DatastoreRepairResultDocument(
        schemaVersion: 1,
        requestId: requestId,
        operation: .repairDatastore,
        status: status,
        message: message,
        updatedAt: "2026-05-22T00:00:00Z"
    )
}
