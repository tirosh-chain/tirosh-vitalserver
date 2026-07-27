import Contracts
import RuntimeControl
import XCTest
@testable import InboundAdapters

final class RuntimeBedHistoryDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeBedHistoryDisplayPolicy()

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

    func testRelationshipReadFailureIsNotRenderedAsZeroEvents() {
        let failed = RuntimeVitalRelationshipHistory(
            state: .readFailed,
            readError: "relationship owner unavailable"
        )

        XCTAssertEqual(
            policy.relationshipEventPageText(failed),
            "Unavailable"
        )
    }

    func testBedSortOptionsExposeExplicitPresentationLabels() {
        XCTAssertEqual(
            RuntimeBedHistoryDisplayPolicy.BedSortOption.allCases.map(\.title),
            ["Name", "Bed ID", "VRecorder", "Last seen", "Status"]
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

    func testSortedBedsCanUseStatusAndExplicitLinkedRecorder() {
        let beds = [
            bed(
                id: "bed-stale",
                name: "OR C",
                vrcode: "VR-B",
                status: .stale
            ),
            bed(
                id: "bed-unknown",
                name: "OR B",
                vrcode: nil,
                status: .unknown
            ),
            bed(
                id: "bed-online",
                name: "OR A",
                vrcode: "VR-A",
                status: .online
            ),
        ]

        XCTAssertEqual(
            policy.sortedBeds(beds, by: .status).map(\.bedID),
            ["bed-online", "bed-stale", "bed-unknown"]
        )
        XCTAssertEqual(
            policy.sortedBeds(beds, by: .recorder).map(\.bedID),
            ["bed-online", "bed-stale", "bed-unknown"]
        )
    }

    private func bed(
        id: String,
        name: String?,
        vrcode: String? = "VR-A",
        status: RuntimeVitalBedStatus = .online,
        lastSeenAt: String? = nil
    ) -> RuntimeVitalBedRecord {
        RuntimeVitalBedRecord(
            bedID: id,
            name: name,
            vrcode: vrcode,
            status: status,
            patientConnected: nil,
            firstSeenAt: nil,
            lastSeenAt: lastSeenAt,
            observationCount: 1,
            currentAnomalyCount: 0,
            latestAnomalySeverity: nil
        )
    }
}
