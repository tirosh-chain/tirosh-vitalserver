import Contracts
import Foundation
import RuntimeControl
import XCTest
@testable import InboundAdapters

final class RuntimeRecorderObservabilityDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeRecorderObservabilityDisplayPolicy()

    func testIncidentQueryUsesExplicitThirtyDayWindowAndLimit() {
        let now = Date(timeIntervalSince1970: 1_728_000_000)

        let query = policy.incidentQuery(vrcode: "06311eba", now: now)

        XCTAssertEqual(query.vrcode, "06311eba")
        XCTAssertEqual(query.from, "2024-09-04T00:00:00Z")
        XCTAssertEqual(query.until, "2024-10-04T00:00:00Z")
        XCTAssertEqual(query.limit, 20)
        XCTAssertNil(query.type)
        XCTAssertNil(query.cursor)
    }

    func testMissingReadingPreservesMissingDetail() {
        let detail = RuntimeRecorderObservabilityDetail.unavailable(
            vrcode: "06311eba",
            readError: "fixture unavailable"
        )

        XCTAssertEqual(
            policy.readingText(detail.readings.temperatureCelsius),
            "missing — health observation is unavailable"
        )
    }

    func testNotReportedEvidenceIsNotRenderedAsHealthy() {
        let detail = RuntimeRecorderObservabilityDetail.unavailable(
            vrcode: "06311eba",
            readError: "fixture unavailable"
        )

        XCTAssertEqual(
            policy.evidenceHealthText(detail.evidenceHealth),
            "Not reported"
        )
    }

    func testUnavailableDetailBootRemainsNotReported() {
        let detail = RuntimeRecorderObservabilityDetail.unavailable(
            vrcode: "06311eba",
            readError: "fixture unavailable"
        )

        XCTAssertEqual(
            policy.bootText(detail, timeText: { $0 ?? "missing" }),
            "Not reported"
        )
    }

    func testMissingRecorderSummaryDoesNotManufactureMismatch() {
        let detail = RuntimeRecorderObservabilityDetail.unavailable(
            vrcode: "06311eba",
            readError: "fixture unavailable"
        )

        XCTAssertFalse(policy.summaryMismatch(detail: detail, summary: nil))
        XCTAssertEqual(policy.operationalHealthSummary(nil), "Unknown · report Not evaluated")
    }
}
