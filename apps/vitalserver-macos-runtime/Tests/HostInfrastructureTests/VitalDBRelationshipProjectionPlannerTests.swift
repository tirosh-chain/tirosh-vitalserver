import Contracts
import HostInfrastructure
import XCTest

final class VitalDBRelationshipProjectionPlannerTests: XCTestCase {
    func testPlansObservationRelationshipAnomaliesWithoutSQLiteState() {
        let planner = VitalDBRelationshipProjectionPlanner()
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_DUP", online: true),
                VitalDBRecorderObservation(vrcode: "VR_FREE", online: true),
                VitalDBRecorderObservation(vrcode: "VR_STALE", online: false),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "A", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-b", name: "B", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-c", name: "C", vrcode: nil, online: true),
                VitalDBBedObservation(bedID: "bed-d", name: "D", vrcode: "VR_STALE", online: true),
            ]
        )

        let events = planner.plannedEvents(for: observation)
        let eventTypes = Set(events.map(\.eventType))

        XCTAssertTrue(eventTypes.contains(.duplicateAssignment))
        XCTAssertTrue(eventTypes.contains(.unlinkedBed))
        XCTAssertTrue(eventTypes.contains(.unlinkedRecorder))
        XCTAssertTrue(eventTypes.contains(.staleLink))
        XCTAssertFalse(eventTypes.contains(.handoff))
        XCTAssertTrue(events.contains {
            $0.eventType == .duplicateAssignment
                && $0.vrcode == "VR_DUP"
                && $0.message.contains("bed-a")
                && $0.message.contains("bed-b")
        })
        XCTAssertTrue(events.contains {
            $0.eventType == .unlinkedRecorder
                && $0.vrcode == "VR_FREE"
                && $0.severity == .warning
        })
        XCTAssertTrue(events.contains {
            $0.eventType == .staleLink
                && $0.bedID == "bed-d"
                && $0.vrcode == "VR_STALE"
        })
    }
}
