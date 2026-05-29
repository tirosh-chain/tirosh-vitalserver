import Contracts
import Core
import XCTest

final class GuestShutdownEvaluatorTests: XCTestCase {
    func testEvaluatesMissingAndRunningResultsAsWait() {
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(nil, expectedRequestId: "request-1"),
            .wait(message: "waiting for guest update shutdown worker")
        )
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(result(status: .running, requestId: "request-1", message: "stopping"), expectedRequestId: "request-1"),
            .wait(message: "stopping")
        )
    }

    func testEvaluatesReadyAndFailedResults() {
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(result(status: .ready, requestId: "request-1", message: "safe"), expectedRequestId: "request-1"),
            .ready(message: "safe")
        )
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(result(status: .failed, requestId: "request-1", message: "backup failed"), expectedRequestId: "request-1"),
            .failed(message: "backup failed")
        )
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(result(status: .ready, requestId: "old", message: "old"), expectedRequestId: "request-1"),
            .failed(message: "guest update shutdown result does not match the current request")
        )
    }

    func testWaiterStopsOnReady() {
        var results: [GuestUpdateShutdownResultDocument?] = [
            nil,
            result(status: .running, requestId: "request-1", message: "running"),
            result(status: .ready, requestId: "request-1", message: "ready"),
        ]
        var progress: [String] = []
        var sleepCount = 0

        let waitResult = GuestShutdownWaiter.wait(
            expectedRequestId: "request-1",
            configuration: GuestShutdownWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
            loadResult: { results.removeFirst() },
            onProgress: { progress.append($0) },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .ready(message: "ready"))
        XCTAssertEqual(progress, ["waiting for guest update shutdown worker", "running"])
        XCTAssertEqual(sleepCount, 2)
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
}
