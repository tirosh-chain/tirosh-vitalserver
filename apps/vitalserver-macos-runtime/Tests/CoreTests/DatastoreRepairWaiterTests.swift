import Core
import Contracts
import XCTest

final class DatastoreRepairWaiterTests: XCTestCase {
    func testCompletesWhenResultBecomesCompleted() {
        var results: [DatastoreRepairResultDocument?] = [
            nil,
            result(status: .running, requestId: "request-1", message: "running"),
            result(status: .completed, requestId: "request-1", message: "done"),
        ]
        var sleepCount = 0

        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
            loadResult: { results.removeFirst() },
            onProgress: { _ in },
            onStale: { _ in },
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
            loadResult: { result(status: .failed, requestId: "request-1", message: "failed") },
            onProgress: { _ in },
            onStale: { _ in },
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
            loadResult: { nil },
            onProgress: { progressMessages.append($0) },
            onStale: { _ in },
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

    func testStaleResultsAreReportedAndIgnoredUntilTimeout() {
        var staleMessages: [String] = []

        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: "request-1",
            configuration: DatastoreRepairWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { result(status: .completed, requestId: "old", message: "old done") },
            onProgress: { _ in },
            onStale: { staleMessages.append($0) },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .timedOut)
        XCTAssertEqual(staleMessages, [
            "stale datastore repair result",
            "stale datastore repair result",
        ])
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
