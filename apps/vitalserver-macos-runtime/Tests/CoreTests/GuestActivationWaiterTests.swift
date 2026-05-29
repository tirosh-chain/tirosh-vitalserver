import Core
import Contracts
import XCTest

final class GuestActivationWaiterTests: XCTestCase {
    func testCompletesWhenResultBecomesCompleted() {
        var results: [GuestUpdateActivationResultDocument?] = [
            nil,
            result(status: .running, requestId: "request-1", message: "running"),
            result(status: .completed, requestId: "request-1", message: "done"),
        ]
        var sleepCount = 0

        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
            loadResult: { results.removeFirst() },
            onProgress: { _ in },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .completed(message: "done"))
        XCTAssertEqual(sleepCount, 2)
    }

    func testFailsImmediatelyOnFailedResult() {
        var sleepCount = 0

        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
            loadResult: { result(status: .failed, requestId: "request-1", message: "failed") },
            onProgress: { _ in },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .failed(message: "failed"))
        XCTAssertEqual(sleepCount, 0)
    }

    func testTimesOutAndReportsProgressOnConfiguredCadence() {
        var progressMessages: [String] = []
        var sleepCount = 0

        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 2),
            loadResult: { nil },
            onProgress: { progressMessages.append($0) },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(waitResult, .timedOut)
        XCTAssertEqual(progressMessages, [
            "waiting for guest update activation worker",
            "waiting for guest update activation worker",
            "waiting for guest update activation worker",
        ])
        XCTAssertEqual(sleepCount, 4)
    }

    func testMismatchedRequestResultFailsImmediately() {
        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { result(status: .completed, requestId: "old", message: "old done") },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "guest update activation result does not match the current request"))
    }

    private func result(
        status: GuestActivationStatus,
        requestId: String,
        message: String
    ) -> GuestUpdateActivationResultDocument {
        GuestUpdateActivationResultDocument(
            schemaVersion: 2,
            requestId: requestId,
            operation: .activateGuestUpdate,
            status: status,
            message: message,
            updatedAt: "2026-05-21T12:33:57Z"
        )
    }
}
