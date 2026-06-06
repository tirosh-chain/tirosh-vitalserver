import Application
import Contracts
import Domain
import XCTest
import Errors

final class DatastoreRepairWaiterTests: XCTestCase {
    func testCompletesWhenResultBecomesCompleted() {
        var results: [RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "running")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ]
        var sleepCount = 0

        let waitResult = runDatastoreRepairWait(
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

        let waitResult = runDatastoreRepairWait(
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

        let waitResult = runDatastoreRepairWait(
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
        let waitResult = runDatastoreRepairWait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .loaded(result(status: .completed, requestId: "old", message: "old done")) },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "datastore repair result does not match the current request"))
    }

    func testReadFailureFailsImmediately() {
        let waitResult = runDatastoreRepairWait(
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

private func runDatastoreRepairWait(
    expectedRequestId: String,
    configuration: DatastoreRepairWaitConfiguration,
    loadResult: () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>,
    onProgress: (String) -> Void,
    sleep: () -> Void
) -> DatastoreRepairWaitResult {
    for attempt in 0..<configuration.maxAttempts {
        switch DatastoreRepairWaiter.evaluateAttempt(
            expectedRequestId: expectedRequestId,
            configuration: configuration,
            attempt: attempt,
            loadResult: loadResult()
        ) {
        case .completed(let message):
            return .completed(message: message)
        case .failed(let message):
            return .failed(message: message)
        case .waiting(let message, let shouldPublishProgress):
            if shouldPublishProgress {
                onProgress(message)
            }
            if attempt < configuration.maxAttempts - 1 {
                sleep()
            }
        }
    }
    return .timedOut
}
