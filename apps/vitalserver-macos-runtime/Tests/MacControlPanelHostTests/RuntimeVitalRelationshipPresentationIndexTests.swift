import Contracts
import RuntimeControl
import XCTest
@testable import InboundAdapters

final class RuntimeVitalRelationshipPresentationIndexTests: XCTestCase {
    func testIndexKeepsOnlyVisibleBedHistoryInsteadOfFilteringFullHistoryDuringRender() {
        let assignments = (0..<10).map { index in
            assignment(index: index, bedID: "bed-a", vrcode: "VR-A")
        } + [assignment(index: 10, bedID: "bed-b", vrcode: "VR-B")]
        let events = (0..<10).map { index in
            event(index: index, bedID: "bed-a", vrcode: "VR-A")
        } + [event(index: 10, bedID: "bed-b", vrcode: "VR-B")]
        let index = RuntimeVitalRelationshipPresentationIndex(
            history: RuntimeVitalRelationshipHistory(
                assignments: assignments,
                events: events,
                eventTotalCount: events.count,
                eventLimit: events.count
            )
        )

        let history = index.history(bedID: "bed-a")

        XCTAssertEqual(history.assignments.map(\.assignmentID), (0..<8).map { "assignment-\($0)" })
        XCTAssertEqual(history.events.map(\.eventID), (0..<8).map { "event-\($0)" })
    }

    func testIndexIncludesHandoffEventForPreviousRecorder() {
        let handoff = RuntimeVitalRelationshipEventRecord(
            eventID: "handoff-1",
            observedAt: "2026-07-22T00:00:00Z",
            eventType: .handoff,
            severity: .info,
            bedID: "bed-a",
            bedName: "OR-A",
            vrcode: "VR-B",
            previousVrcode: "VR-A",
            previousBedID: nil,
            message: "Bed VRecorder assignment changed."
        )
        let index = RuntimeVitalRelationshipPresentationIndex(
            history: RuntimeVitalRelationshipHistory(events: [handoff])
        )

        XCTAssertEqual(index.history(vrcode: "VR-A").events.map(\.eventID), ["handoff-1"])
        XCTAssertEqual(index.history(vrcode: "VR-B").events.map(\.eventID), ["handoff-1"])
    }

    private func assignment(
        index: Int,
        bedID: String,
        vrcode: String
    ) -> RuntimeVitalBedAssignmentRecord {
        RuntimeVitalBedAssignmentRecord(
            assignmentID: "assignment-\(index)",
            bedID: bedID,
            bedName: nil,
            vrcode: vrcode,
            startedAt: "2026-07-22T00:00:00Z",
            endedAt: nil,
            lastSeenAt: nil,
            lastObservedAt: "2026-07-22T00:00:00Z",
            status: .online,
            patientConnected: nil,
            observationCount: 1
        )
    }

    private func event(
        index: Int,
        bedID: String,
        vrcode: String
    ) -> RuntimeVitalRelationshipEventRecord {
        RuntimeVitalRelationshipEventRecord(
            eventID: "event-\(index)",
            observedAt: "2026-07-22T00:00:00Z",
            eventType: .staleLink,
            severity: .warning,
            bedID: bedID,
            bedName: nil,
            vrcode: vrcode,
            previousVrcode: nil,
            previousBedID: nil,
            message: "Bed and VRecorder online state differ."
        )
    }
}
