@testable import MacControlPanelHost
import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeVitalRecorderDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeVitalRecorderDisplayPolicy()

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
        XCTAssertEqual(policy.patientText(true), "Connected")
        XCTAssertEqual(policy.patientText(false), "Not connected")
        XCTAssertEqual(policy.patientText(nil), "Patient connection not reported")

        XCTAssertEqual(policy.reportedText("  ", missing: "IP not reported"), "IP not reported")
        XCTAssertEqual(policy.reportedText(nil, missing: "IP not reported"), "IP not reported")
        XCTAssertEqual(policy.reportedText("10.0.0.2", missing: "IP not reported"), "10.0.0.2")
    }

    func testRecorderAnomalyTextDistinguishesHistoryFromCurrentZero() {
        XCTAssertEqual(policy.recorderAnomalyText(recorder(currentAnomalyCount: 0)), "-")
        XCTAssertEqual(policy.recorderAnomalyText(recorder(currentAnomalyCount: 3)), "3")
        XCTAssertEqual(
            policy.recorderAnomalyText(recorder(currentAnomalyCount: 3, presentInLatestObservation: false)),
            "History"
        )
    }

    func testBytesPerSecondTextBoundsNegativeValuesAndKeepsSmallRatesVisible() {
        XCTAssertEqual(policy.bytesPerSecondText(-4), "Zero bytes/s")
        XCTAssertEqual(policy.bytesPerSecondText(0.4), "0.40 B/s")
        XCTAssertEqual(policy.bytesPerSecondText(1536), "2 KB/s")
    }

    private func recorder(
        currentAnomalyCount: Int,
        presentInLatestObservation: Bool = true
    ) -> RuntimeVitalRecorderRecord {
        RuntimeVitalRecorderRecord(
            vrcode: "vr-1",
            status: .online,
            lastIP: nil,
            version: nil,
            bedID: nil,
            bedName: nil,
            patientConnected: nil,
            firstSeenAt: nil,
            lastSeenAt: nil,
            observationCount: 1,
            currentAnomalyCount: currentAnomalyCount,
            latestAnomalySeverity: nil,
            presentInLatestObservation: presentInLatestObservation
        )
    }
}
