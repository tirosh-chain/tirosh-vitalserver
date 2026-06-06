import Contracts
import Application
import Domain
import XCTest
import Errors

final class GuestShutdownEvaluatorTests: XCTestCase {
    func testEvaluatesMissingResultSeparatelyFromRunningResult() {
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(nil, expectedRequestId: "request-1"),
            .missing(message: "waiting for guest update shutdown worker")
        )
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(result(status: .running, requestId: "request-1", message: "stopping"), expectedRequestId: "request-1"),
            .wait(message: "stopping")
        )
    }

    func testEvaluatesReadyAndFailedResults() {
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(
                result(
                    status: .ready,
                    requestId: "request-1",
                    message: "safe",
                    shutdownPhase: .poweroffRequested
                ),
                expectedRequestId: "request-1"
            ),
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

    func testReadyResultRequiresExplicitPoweroffPhase() {
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(
                result(status: .ready, requestId: "request-1", message: "legacy ready"),
                expectedRequestId: "request-1"
            ),
            .failed(message: "guest update shutdown ready result is missing shutdownPhase")
        )
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(
                result(
                    status: .ready,
                    requestId: "request-1",
                    message: "prepared",
                    shutdownPhase: .prepared
                ),
                expectedRequestId: "request-1"
            ),
            .wait(message: "prepared")
        )
        XCTAssertEqual(
            GuestShutdownEvaluator.evaluate(
                result(
                    status: .ready,
                    requestId: "request-1",
                    message: "poweroff failed",
                    shutdownPhase: .poweroffFailed
                ),
                expectedRequestId: "request-1"
            ),
            .failed(message: "poweroff failed")
        )
    }

    func testWaiterStopsOnReady() {
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "running")),
            .loaded(result(
                status: .ready,
                requestId: "request-1",
                message: "ready",
                shutdownPhase: .poweroffRequested
            )),
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

    func testWaiterFailsOnReadFailure() {
        let waitResult = GuestShutdownWaiter.wait(
            expectedRequestId: "request-1",
            configuration: GuestShutdownWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .failed("invalid json") },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "failed to read guest update shutdown result: invalid json"))
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
}
