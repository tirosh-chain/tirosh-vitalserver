import Contracts
import RuntimeControl
import XCTest
@testable import InboundAdapters

final class RuntimeBedHistoryDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeBedHistoryDisplayPolicy()

    func testBedTableUsesBoundedFixedWidthForStandardPanel() {
        XCTAssertLessThanOrEqual(RuntimeBedTableLayout.contentWidth, 1_100)
        XCTAssertGreaterThan(RuntimeBedTableLayout.bedWidth, 0)
        XCTAssertGreaterThan(RuntimeBedTableLayout.dataIssueWidth, 0)
    }

    func testLoadedEmptyHistoryRemainsDistinctFromReadFailure() {
        let loaded = RuntimeVitalBedHistory(
            state: .loaded,
            beds: [],
            readError: nil
        )
        let failed = RuntimeVitalBedHistory.failed(
            readError: "bed owner unavailable"
        )

        XCTAssertEqual(policy.readPresentation(loaded), .loaded)
        XCTAssertEqual(
            policy.readPresentation(failed),
            .readFailed("bed owner unavailable")
        )
        XCTAssertEqual(policy.summaryText(0, history: loaded), "0")
        XCTAssertEqual(policy.summaryText(0, history: failed), "Unavailable")
    }

    func testPartialHistoryPreservesRowsAndReportedIssue() {
        let partial = RuntimeVitalBedHistory(
            state: .partiallyLoaded,
            beds: [],
            readError: "one Bed projection failed"
        )

        XCTAssertEqual(
            policy.readPresentation(partial),
            .partiallyLoaded("one Bed projection failed")
        )
        XCTAssertEqual(policy.summaryText(2, history: partial), "2")
    }

    func testBedSortOptionsExposeExplicitPresentationLabels() {
        XCTAssertEqual(
            RuntimeBedHistoryDisplayPolicy.BedSortOption.allCases.map(\.title),
            ["Name", "Bed ID", "Patient", "Last seen", "Status"]
        )
    }

    func testSortedBedsKeepMissingNamesAndTimesDistinct() {
        let beds = [
            bed(
                id: "bed-missing",
                name: nil,
                lastSeenAt: nil
            ),
            bed(
                id: "bed-old",
                name: "OR B",
                lastSeenAt: "2026-07-27T01:00:00Z"
            ),
            bed(
                id: "bed-new",
                name: "OR A",
                lastSeenAt: "2026-07-27T03:00:00Z"
            ),
        ]

        XCTAssertEqual(
            policy.sortedBeds(beds, by: .name).map(\.bedID),
            ["bed-new", "bed-old", "bed-missing"]
        )
        XCTAssertEqual(
            policy.sortedBeds(beds, by: .lastSeen).map(\.bedID),
            ["bed-new", "bed-old", "bed-missing"]
        )
    }

    func testSortedBedsCanUseStatusAndPatientPresence() {
        let beds = [
            bed(
                id: "bed-stale",
                name: "OR C",
                status: .stale,
                patientConnected: false
            ),
            bed(
                id: "bed-unknown",
                name: "OR B",
                status: .unknown,
                patientConnected: nil
            ),
            bed(
                id: "bed-online",
                name: "OR A",
                status: .online,
                patientConnected: true
            ),
        ]

        XCTAssertEqual(
            policy.sortedBeds(beds, by: .status).map(\.bedID),
            ["bed-online", "bed-stale", "bed-unknown"]
        )
        XCTAssertEqual(
            policy.sortedBeds(beds, by: .patient).map(\.bedID),
            ["bed-online", "bed-stale", "bed-unknown"]
        )
    }

    private func bed(
        id: String,
        name: String?,
        status: RuntimeVitalBedStatus = .online,
        lastSeenAt: String? = nil,
        patientConnected: Bool? = nil
    ) -> RuntimeVitalBedRecord {
        RuntimeVitalBedRecord(
            bedID: id,
            name: name,
            vrcode: nil,
            status: status,
            patientConnected: patientConnected,
            firstSeenAt: nil,
            lastSeenAt: lastSeenAt,
            observationCount: 1,
            currentAnomalyCount: 0,
            latestAnomalySeverity: nil
        )
    }
}
