import Contracts
@testable import Domain
import XCTest
import Errors

final class VitalDBRelationshipProjectionPlanTests: XCTestCase {
    func testPlansUpdateForUnchangedOpenAssignment() {
        let plan = VitalDBRelationshipProjectionPlanner().projectionPlan(
            for: VitalDBObservationDocument(
                observedAt: "2026-05-25T00:01:00Z",
                ready: true,
                recorderOnlineThresholdSeconds: 120,
                beds: [
                    VitalDBBedObservation(
                        bedID: "bed-a",
                        name: "OR A",
                        vrcode: "VR_A",
                        lastSeenAt: "2026-05-25T00:01:00Z",
                        patientConnected: true,
                        online: true
                    ),
                ]
            ),
            openAssignmentsByBedID: [
                "bed-a": assignment(bedID: "bed-a", vrcode: "VR_A", startedAt: "2026-05-25T00:00:00Z"),
            ]
        )

        XCTAssertEqual(plan.assignmentCommands, [
            .update(VitalDBBedAssignmentUpdateCommand(
                assignmentID: "assignment:bed-a:VR_A:2026-05-25T00:00:00Z",
                bedName: "OR A",
                lastSeenAt: "2026-05-25T00:01:00Z",
                lastObservedAt: "2026-05-25T00:01:00Z",
                status: .online,
                patientConnected: true
            )),
        ])
        XCTAssertFalse(plan.relationshipEvents.contains { $0.eventType == .handoff })
    }

    func testPlansCloseForUnlinkedBedWithoutInventingReplacementAssignment() {
        let plan = VitalDBRelationshipProjectionPlanner().projectionPlan(
            for: VitalDBObservationDocument(
                observedAt: "2026-05-25T00:02:00Z",
                ready: true,
                recorderOnlineThresholdSeconds: 120,
                beds: [
                    VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: nil, online: true),
                ]
            ),
            openAssignmentsByBedID: [
                "bed-a": assignment(bedID: "bed-a", vrcode: "VR_A", startedAt: "2026-05-25T00:00:00Z"),
            ]
        )

        XCTAssertEqual(plan.assignmentCommands, [
            .close(VitalDBBedAssignmentCloseCommand(
                assignmentID: "assignment:bed-a:VR_A:2026-05-25T00:00:00Z",
                endedAt: "2026-05-25T00:02:00Z"
            )),
        ])
        XCTAssertTrue(plan.relationshipEvents.contains {
            $0.eventType == .unlinkedBed && $0.bedID == "bed-a"
        })
    }

    func testPlansHandoffAsCloseEventAndInsertFromExplicitOpenAssignment() {
        let plan = VitalDBRelationshipProjectionPlanner().projectionPlan(
            for: VitalDBObservationDocument(
                observedAt: "2026-05-25T00:05:00Z",
                ready: true,
                recorderOnlineThresholdSeconds: 120,
                beds: [
                    VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_B", online: false),
                ]
            ),
            openAssignmentsByBedID: [
                "bed-a": assignment(bedID: "bed-a", vrcode: "VR_A", startedAt: "2026-05-25T00:00:00Z"),
            ]
        )

        XCTAssertEqual(plan.assignmentCommands, [
            .close(VitalDBBedAssignmentCloseCommand(
                assignmentID: "assignment:bed-a:VR_A:2026-05-25T00:00:00Z",
                endedAt: "2026-05-25T00:05:00Z"
            )),
            .insert(VitalDBBedAssignmentInsertCommand(
                assignmentID: "assignment:bed-a:VR_B:2026-05-25T00:05:00Z",
                bedID: "bed-a",
                bedName: "OR A",
                vrcode: "VR_B",
                startedAt: "2026-05-25T00:05:00Z",
                lastSeenAt: nil,
                lastObservedAt: "2026-05-25T00:05:00Z",
                status: .stale,
                patientConnected: nil
            )),
        ])
        XCTAssertTrue(plan.relationshipEvents.contains {
            $0.id == "relationship:handoff:2026-05-25T00:05:00Z:bed-a:VR_B:VR_A"
                && $0.eventType == .handoff
                && $0.previousVrcode == "VR_A"
        })
    }
}

private func assignment(
    bedID: String,
    vrcode: String,
    startedAt: String
) -> VitalDBBedAssignmentRecord {
    VitalDBBedAssignmentRecord(
        id: "assignment:\(bedID):\(vrcode):\(startedAt)",
        bedID: bedID,
        bedName: "OR A",
        vrcode: vrcode,
        startedAt: startedAt,
        endedAt: nil,
        lastSeenAt: startedAt,
        lastObservedAt: startedAt,
        status: .online,
        patientConnected: true,
        observationCount: 1
    )
}
