import Core
import Contracts
import XCTest

final class GuestBootstrapEvaluatorTests: XCTestCase {
    func testDocumentLoadResultPreservesMissingUnavailableAndLoadedStates() {
        XCTAssertEqual(GuestBootstrapEvaluator.assess(.missing), .missing)
        XCTAssertEqual(GuestBootstrapEvaluator.assess(.failed("permission denied")), .unavailable("permission denied"))
        XCTAssertEqual(
            GuestBootstrapEvaluator.assess(.loaded(result(status: .running, reasonCodes: nil))),
            .noFailure
        )
    }

    func testRunningAndCompletedResultsDoNotFailEarly() {
        XCTAssertEqual(GuestBootstrapEvaluator.assess(result(status: .running, reasonCodes: nil)), .noFailure)
        XCTAssertEqual(GuestBootstrapEvaluator.assess(result(status: .completed, reasonCodes: [])), .noFailure)
        XCTAssertNil(GuestBootstrapEvaluator.failureReason(result(status: .running, reasonCodes: nil)))
        XCTAssertNil(GuestBootstrapEvaluator.failureReason(result(status: .completed, reasonCodes: [])))
    }

    func testFailedResultUsesFirstReasonCode() {
        XCTAssertEqual(
            GuestBootstrapEvaluator.assess(result(
                status: .failed,
                reasonCodes: [.guestBootstrapMissingRuntimePackages, .guestBootstrapFailed]
            )),
            .failed(.guestBootstrapMissingRuntimePackages)
        )
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
            GuestBootstrapEvaluator.assess(result(status: .failed, reasonCodes: nil)),
            .failed(.guestBootstrapFailed)
        )
        XCTAssertEqual(
            GuestBootstrapEvaluator.failureReason(result(status: .failed, reasonCodes: nil)),
            .guestBootstrapFailed
        )
    }

    func testUnknownStatusFailsGeneric() {
        XCTAssertEqual(
            GuestBootstrapEvaluator.assess(result(status: .unknown("paused"), reasonCodes: nil)),
            .failed(.guestBootstrapFailed)
        )
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
