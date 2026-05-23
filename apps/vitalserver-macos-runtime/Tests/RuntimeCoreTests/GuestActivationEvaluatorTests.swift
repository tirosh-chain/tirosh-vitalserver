import RuntimeCore
import RuntimeContracts
import XCTest

final class GuestActivationEvaluatorTests: XCTestCase {
    func testMissingResultWaits() {
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(nil),
            .wait(message: "waiting for guest update activation worker")
        )
    }

    func testPendingAndRunningWait() {
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(result(status: .pending, message: "queued")),
            .wait(message: "queued")
        )
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(result(status: .running, message: "loading images")),
            .wait(message: "loading images")
        )
    }

    func testCompletedSucceeds() {
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(result(status: .completed, message: "done")),
            .completed(message: "done")
        )
    }

    func testFailedSkippedAndUnknownFail() {
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(result(status: .failed, message: "compose failed")),
            .failed(message: "compose failed")
        )
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(result(status: .skipped, message: "request missing")),
            .failed(message: "request missing")
        )
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(result(status: .unknown("paused"), message: nil)),
            .failed(message: "unknown guest update activation status: paused")
        )
    }

    func testStaleRequestIdIsIgnored() {
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(
                result(status: .completed, requestId: "old", message: "old done"),
                expectedRequestId: "new"
            ),
            .stale(message: "stale guest update activation result")
        )
    }

    func testV2ResultMissingRequestIdIsStaleWhenExpectedRequestIdExists() {
        XCTAssertEqual(
            GuestActivationEvaluator.evaluate(
                result(schemaVersion: 2, status: .completed, requestId: nil, message: "done"),
                expectedRequestId: "new"
            ),
            .stale(message: "guest update activation result is missing requestId")
        )
    }

    private func result(
        schemaVersion: Int? = nil,
        status: GuestActivationStatus,
        requestId: String? = nil,
        message: String?
    ) -> GuestUpdateActivationResultDocument {
        GuestUpdateActivationResultDocument(
            schemaVersion: schemaVersion,
            requestId: requestId,
            operation: .activateGuestUpdate,
            status: status,
            message: message,
            updatedAt: "2026-05-21T12:33:57Z"
        )
    }
}
