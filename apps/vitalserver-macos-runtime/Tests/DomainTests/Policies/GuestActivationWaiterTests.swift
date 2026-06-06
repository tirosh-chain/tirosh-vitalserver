import Application
import Contracts
import Domain
import XCTest
import Errors

final class GuestActivationWaiterTests: XCTestCase {
    func testCompletesWhenResultBecomesCompleted() {
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "running")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ]
        var sleepCount = 0

        let waitResult = runGuestActivationWait(
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

        let waitResult = runGuestActivationWait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 1),
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

        let waitResult = runGuestActivationWait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 5, progressEveryAttempts: 2),
            loadResult: { .missing },
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
        let waitResult = runGuestActivationWait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .loaded(result(status: .completed, requestId: "old", message: "old done")) },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "guest update activation result does not match the current request"))
    }

    func testReadFailureFailsImmediately() {
        let waitResult = runGuestActivationWait(
            expectedRequestId: "request-1",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .failed("permission denied") },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(waitResult, .failed(message: "failed to read guest update activation result: permission denied"))
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

private func runGuestActivationWait(
    expectedRequestId: String,
    configuration: GuestActivationWaitConfiguration,
    loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>,
    onProgress: (String) -> Void,
    sleep: () -> Void
) -> GuestActivationWaitResult {
    for attempt in 0..<configuration.maxAttempts {
        switch GuestActivationWaiter.evaluateAttempt(
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
