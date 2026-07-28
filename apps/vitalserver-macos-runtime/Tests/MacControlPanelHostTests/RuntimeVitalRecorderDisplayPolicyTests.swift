@testable import MacControlPanelHost
import Contracts
import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeVitalRecorderDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeVitalRecorderDisplayPolicy()

    func testRecorderTableLayoutReservesHeaderAndTwoLineIPCellHeight() {
        XCTAssertGreaterThanOrEqual(RuntimeVitalHistoryTableLayout.headerMinimumHeight, 20)
        XCTAssertGreaterThanOrEqual(RuntimeVitalHistoryTableLayout.rowMinimumHeight, 40)
    }

    func testRecorderAndBedStatusTextPreservesExplicitStates() {
        XCTAssertEqual(policy.statusText(RuntimeVitalRecorderStatus.online), "Online")
        XCTAssertEqual(policy.statusText(RuntimeVitalRecorderStatus.stale), "Stale")
        XCTAssertEqual(policy.statusText(RuntimeVitalRecorderStatus.offline), "Offline")
        XCTAssertEqual(policy.statusText(RuntimeVitalRecorderStatus.notObserved), "Not observed")
        XCTAssertEqual(policy.statusText(RuntimeVitalRecorderStatus.unknown), "Unknown")

        XCTAssertEqual(policy.statusText(RuntimeVitalBedStatus.online), "Online")
        XCTAssertEqual(policy.statusText(RuntimeVitalBedStatus.stale), "Stale")
        XCTAssertEqual(policy.statusText(RuntimeVitalBedStatus.offline), "Offline")
        XCTAssertEqual(policy.statusText(RuntimeVitalBedStatus.notObserved), "Not observed")
        XCTAssertEqual(policy.statusText(RuntimeVitalBedStatus.unknown), "Unknown")
    }

    func testStatusToneKeepsActiveWarningAndNeutralDistinct() {
        XCTAssertEqual(policy.statusTone(RuntimeVitalRecorderStatus.online), .active)
        XCTAssertEqual(policy.statusTone(RuntimeVitalRecorderStatus.stale), .warning)
        XCTAssertEqual(policy.statusTone(RuntimeVitalRecorderStatus.offline), .neutral)
        XCTAssertEqual(policy.statusTone(RuntimeVitalRecorderStatus.notObserved), .neutral)
        XCTAssertEqual(policy.statusTone(RuntimeVitalRecorderStatus.unknown), .neutral)

        XCTAssertEqual(policy.statusTone(RuntimeVitalBedStatus.online), .active)
        XCTAssertEqual(policy.statusTone(RuntimeVitalBedStatus.stale), .warning)
        XCTAssertEqual(policy.statusTone(RuntimeVitalBedStatus.offline), .neutral)
        XCTAssertEqual(policy.statusTone(RuntimeVitalBedStatus.notObserved), .neutral)
        XCTAssertEqual(policy.statusTone(RuntimeVitalBedStatus.unknown), .neutral)
    }

    func testPatientAndReportedTextDoNotConvertMissingStateToEmptySuccess() {
        XCTAssertEqual(policy.patientText(true), "Present")
        XCTAssertEqual(policy.patientText(false), "Not present")
        XCTAssertEqual(policy.patientText(nil), "Not reported")

        XCTAssertEqual(policy.reportedText("  ", missing: "IP not reported"), "IP not reported")
        XCTAssertEqual(policy.reportedText(nil, missing: "IP not reported"), "IP not reported")
        XCTAssertEqual(policy.reportedText("10.0.0.2", missing: "IP not reported"), "10.0.0.2")
    }

    func testRecorderSourceUsesExplicitReportedVersion() {
        XCTAssertEqual(policy.recorderSourceText("vitalserver-lab"), "Lab")
        XCTAssertEqual(policy.recorderSourceText("1.2.3"), "Vital Recorder")
        XCTAssertEqual(policy.recorderSourceText(nil), "Not reported")
        XCTAssertEqual(policy.recorderSourceText("   "), "Not reported")
        XCTAssertTrue(policy.isProductLabRecorder(version: "vitalserver-lab"))
        XCTAssertFalse(policy.isProductLabRecorder(version: "LAB-ABC123"))
        XCTAssertFalse(policy.isProductLabRecorder(version: nil))
    }

    func testRecorderAnomalyTextDistinguishesHistoryFromCurrentZero() {
        XCTAssertEqual(policy.recorderAnomalyText(recorder(currentAnomalyCount: 0)), "-")
        XCTAssertEqual(
            policy.recorderAnomalyText(
                recorder(currentAnomalyCount: 3, latestAnomalyKind: .staleRecorder)
            ),
            "Stale Recorder"
        )
        XCTAssertEqual(
            policy.recorderAnomalyText(recorder(currentAnomalyCount: 3, presentInLatestObservation: false)),
            "History"
        )
    }

    func testSortedRecordersDefaultsToStableVrcodeOrder() {
        let recorders = [
            recorder(vrcode: "VR_C", currentAnomalyCount: 0, lastSeenAt: "2026-06-09T01:00:00Z"),
            recorder(vrcode: "VR_A", currentAnomalyCount: 0, lastSeenAt: "2026-06-09T03:00:00Z"),
            recorder(vrcode: "VR_B", currentAnomalyCount: 0, lastSeenAt: "2026-06-09T02:00:00Z"),
        ]

        let sorted = policy.sortedRecorders(recorders, by: .vrcode)

        XCTAssertEqual(sorted.map(\.vrcode), ["VR_A", "VR_B", "VR_C"])
    }

    func testSortedRecordersCanUseLastSeenWithoutTurningMissingIntoEpoch() {
        let recorders = [
            recorder(vrcode: "VR_MISSING", currentAnomalyCount: 0, lastSeenAt: nil),
            recorder(vrcode: "VR_OLD", currentAnomalyCount: 0, lastSeenAt: "2026-06-09T01:00:00Z"),
            recorder(vrcode: "VR_NEW", currentAnomalyCount: 0, lastSeenAt: "2026-06-09T03:00:00Z"),
        ]

        let sorted = policy.sortedRecorders(recorders, by: .lastSeen)

        XCTAssertEqual(sorted.map(\.vrcode), ["VR_NEW", "VR_OLD", "VR_MISSING"])
    }

    func testSortedRecordersCanUseStatusOrBed() {
        let recorders = [
            recorder(vrcode: "VR_STALE", status: .stale, currentAnomalyCount: 0, bedName: "OR C"),
            recorder(vrcode: "VR_UNKNOWN", status: .unknown, currentAnomalyCount: 0, bedName: nil),
            recorder(vrcode: "VR_ONLINE", status: .online, currentAnomalyCount: 0, bedName: "OR A"),
        ]

        XCTAssertEqual(
            policy.sortedRecorders(recorders, by: .status).map(\.vrcode),
            ["VR_ONLINE", "VR_STALE", "VR_UNKNOWN"]
        )
        XCTAssertEqual(
            policy.sortedRecorders(recorders, by: .bed).map(\.vrcode),
            ["VR_ONLINE", "VR_STALE", "VR_UNKNOWN"]
        )
    }

    func testBytesPerSecondTextBoundsNegativeValuesAndKeepsSmallRatesVisible() {
        XCTAssertEqual(policy.bytesPerSecondText(-4), "Zero bytes/s")
        XCTAssertEqual(policy.bytesPerSecondText(0.4), "0.40 B/s")
        XCTAssertEqual(policy.bytesPerSecondText(1536), "2 KB/s")
    }

    private func recorder(
        vrcode: String = "vr-1",
        status: RuntimeVitalRecorderStatus = .online,
        currentAnomalyCount: Int,
        latestAnomalyKind: VitalDBAnomalyKind? = nil,
        lastSeenAt: String? = nil,
        bedName: String? = nil,
        presentInLatestObservation: Bool = true
    ) -> RuntimeVitalRecorderRecord {
        RuntimeVitalRecorderRecord(
            vrcode: vrcode,
            status: status,
            lastIP: nil,
            version: nil,
            bedID: nil,
            bedName: bedName,
            patientConnected: nil,
            firstSeenAt: nil,
            lastSeenAt: lastSeenAt,
            observationCount: 1,
            currentAnomalyCount: currentAnomalyCount,
            latestAnomalyKind: latestAnomalyKind,
            latestAnomalySeverity: nil,
            presentInLatestObservation: presentInLatestObservation
        )
    }

}
