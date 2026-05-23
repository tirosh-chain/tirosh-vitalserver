import Core
import Contracts
import XCTest

final class GuestBootstrapEvaluatorTests: XCTestCase {
    func testMissingRunningAndCompletedResultsDoNotFailEarly() {
        XCTAssertNil(GuestBootstrapEvaluator.failureReason(nil))
        XCTAssertNil(GuestBootstrapEvaluator.failureReason(result(status: .running, reasonCodes: nil)))
        XCTAssertNil(GuestBootstrapEvaluator.failureReason(result(status: .completed, reasonCodes: [])))
    }

    func testFailedResultUsesFirstReasonCode() {
        XCTAssertEqual(
            GuestBootstrapEvaluator.failureReason(result(
                status: .failed,
                reasonCodes: [.guestBootstrapMissingRuntimePackages, .guestBootstrapFailed]
            )),
            .guestBootstrapMissingRuntimePackages
        )
    }

    func testFailedResultWithoutReasonFallsBackToGenericBootstrapFailure() {
        XCTAssertEqual(
            GuestBootstrapEvaluator.failureReason(result(status: .failed, reasonCodes: nil)),
            .guestBootstrapFailed
        )
    }

    func testUnknownStatusFailsGeneric() {
        XCTAssertEqual(
            GuestBootstrapEvaluator.failureReason(result(status: .unknown("paused"), reasonCodes: nil)),
            .guestBootstrapFailed
        )
    }

    private func result(
        status: GuestBootstrapStatus,
        reasonCodes: [RuntimeFailureReason]?
    ) -> GuestBootstrapResultDocument {
        GuestBootstrapResultDocument(
            schemaVersion: 2,
            operation: .unknown("bootstrap"),
            status: status,
            message: nil,
            reasonCodes: reasonCodes,
            updatedAt: "2026-05-21T12:34:57Z"
        )
    }
}
