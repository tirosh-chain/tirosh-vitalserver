import Core
import Contracts
import XCTest

final class DatastoreRepairWaiterTests: XCTestCase {
    func testCompletesWhenResultBecomesCompleted() {
        var results: [RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "running")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ]
        var sleepCount = 0

        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
            loadResult: { results.removeFirst() },
            onProgress: { _ in },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .completed(message: "done"))
        XCTAssertEqual(sleepCount, 2)
    }

    func testFailsImmediatelyOnFailedResult() {
        var sleepCount = 0

        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
            loadResult: { .loaded(result(status: .failed, requestId: "request-1", message: "failed")) },
            onProgress: { _ in },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .failed(message: "failed"))
        XCTAssertEqual(sleepCount, 0)
    }

    func testTimesOutAndReportsProgressOnConfiguredCadence() {
        var progressMessages: [String] = []
        var sleepCount = 0

        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 2),
            loadResult: { .missing },
            onProgress: { progressMessages.append($0) },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .timedOut)
        XCTAssertEqual(progressMessages, [
            "waiting for datastore repair guest worker",
            "waiting for datastore repair guest worker",
            "waiting for datastore repair guest worker",
        ])
        XCTAssertEqual(sleepCount, 4)
    }

    func testMismatchedRequestResultFailsImmediately() {
        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .loaded(result(status: .completed, requestId: "old", message: "old done")) },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "datastore repair result does not match the current request"))
    }

    func testReadFailureFailsImmediately() {
        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .failed("decode failed") },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "failed to read datastore repair result: decode failed"))
    }

    private func result(
        status: DatastoreRepairStatus,
        requestId: String,
        message: String
    ) -> DatastoreRepairResultDocument {
        DatastoreRepairResultDocument(
            schemaVersion: 2,
            requestId: requestId,
            operation: .repairDatastore,
            status: status,
            message: message,
            updatedAt: "2026-05-21T12:33:57Z"
        )
    }
}
