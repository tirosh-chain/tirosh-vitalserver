import Application
import Contracts
import Domain
import XCTest
import Errors

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

    func testCurrentBootAssessmentRejectsBootstrapResultFromDifferentBoot() {
        let assessment: GuestBootstrapAssessment = GuestBootstrapEvaluator.assessCurrentBoot(
            .loaded(result(status: .failed, reasonCodes: [.guestBootstrapFailed], bootID: "old-boot")),
            currentBootID: "current-boot",
            now: date("2026-05-21T12:35:00Z"),
            graceSeconds: 60
        )

        XCTAssertEqual(assessment, GuestBootstrapAssessment.notCurrentBoot)
    }

    func testCurrentBootAssessmentAllowsFreshBootstrapResultWhenGuestBootIDIsMissing() {
        let assessment: GuestBootstrapAssessment = GuestBootstrapEvaluator.assessCurrentBoot(
            .loaded(result(status: .failed, reasonCodes: [.guestBootstrapFailed], bootID: "boot-1")),
            currentBootID: nil,
            now: date("2026-05-21T12:35:00Z"),
            graceSeconds: 60
        )

        XCTAssertEqual(assessment, GuestBootstrapAssessment.failed(.guestBootstrapFailed))
    }

    func testCurrentBootAssessmentRejectsStaleBootstrapResultWhenGuestBootIDIsMissing() {
        let assessment: GuestBootstrapAssessment = GuestBootstrapEvaluator.assessCurrentBoot(
            .loaded(result(status: .failed, reasonCodes: [.guestBootstrapFailed], bootID: "boot-1")),
            currentBootID: nil,
            now: date("2026-05-21T12:40:00Z"),
            graceSeconds: 60
        )

        XCTAssertEqual(assessment, GuestBootstrapAssessment.notCurrentBoot)
    }

    private func result(
        status: GuestBootstrapStatus,
        reasonCodes: [RuntimeFailureReason]?,
        bootID: String? = nil
    ) -> GuestBootstrapResultDocument {
        GuestBootstrapResultDocument(
            schemaVersion: 2,
            bootID: bootID,
            operation: .unknown("bootstrap"),
            status: status,
            message: nil,
            reasonCodes: reasonCodes,
            updatedAt: "2026-05-21T12:34:57Z"
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
