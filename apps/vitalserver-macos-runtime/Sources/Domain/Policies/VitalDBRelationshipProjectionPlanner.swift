import Contracts
import Foundation

public struct VitalDBRelationshipProjectionPlanner {
    public init() {}

    public func projectionPlan(
        for observation: VitalDBObservationDocument,
        openAssignmentsByBedID: [String: VitalDBBedAssignmentRecord]
    ) -> VitalDBRelationshipProjectionPlan {
        let observedAt = observation.observedAt
        var assignmentCommands: [VitalDBBedAssignmentProjectionCommand] = []
        var relationshipEvents: [VitalDBRelationshipEventRecord] = []

        for bed in observation.beds.sorted(by: { $0.bedID < $1.bedID }) {
            guard let vrcode = bed.vrcode, !vrcode.isEmpty else {
                if let openAssignment = openAssignmentsByBedID[bed.bedID] {
                    assignmentCommands.append(.close(VitalDBBedAssignmentCloseCommand(
                        assignmentID: openAssignment.id,
                        endedAt: observedAt
                    )))
                }
                continue
            }

            if let openAssignment = openAssignmentsByBedID[bed.bedID] {
                if openAssignment.vrcode == vrcode {
                    assignmentCommands.append(.update(VitalDBBedAssignmentUpdateCommand(
                        assignmentID: openAssignment.id,
                        bedName: bed.name,
                        lastSeenAt: bed.lastSeenAt,
                        lastObservedAt: observedAt,
                        status: bed.online ? .online : .stale,
                        patientConnected: bed.patientConnected
                    )))
                } else {
                    assignmentCommands.append(.close(VitalDBBedAssignmentCloseCommand(
                        assignmentID: openAssignment.id,
                        endedAt: observedAt
                    )))
                    relationshipEvents.append(VitalDBRelationshipEventRecord(
                        id: Self.eventID(.handoff, observedAt, bed.bedID, vrcode, openAssignment.vrcode),
                        observedAt: observedAt,
                        eventType: .handoff,
                        severity: .info,
                        bedID: bed.bedID,
                        bedName: bed.name,
                        vrcode: vrcode,
                        previousVrcode: openAssignment.vrcode,
                        previousBedID: nil,
                        message: "Bed VRecorder assignment changed."
                    ))
                    assignmentCommands.append(.insert(insertCommand(for: bed, vrcode: vrcode, observedAt: observedAt)))
                }
            } else {
                assignmentCommands.append(.insert(insertCommand(for: bed, vrcode: vrcode, observedAt: observedAt)))
            }
        }

        relationshipEvents.append(contentsOf: plannedEvents(for: observation))
        return VitalDBRelationshipProjectionPlan(
            assignmentCommands: assignmentCommands,
            relationshipEvents: relationshipEvents
        )
    }

    public func plannedEvents(for observation: VitalDBObservationDocument) -> [VitalDBRelationshipEventRecord] {
        let observedAt = observation.observedAt
        let recordersByVrcode = Dictionary(
            observation.recorders.map { ($0.vrcode, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let linkedBedVrcodes = Set(observation.beds.compactMap(\.vrcode).filter { !$0.isEmpty })
        let bedsByVrcode = Dictionary(grouping: observation.beds.compactMap { bed in
            bed.vrcode.map { ($0, bed) }
        }, by: \.0)

        var events: [VitalDBRelationshipEventRecord] = []
        for bed in observation.beds.sorted(by: { $0.bedID < $1.bedID }) {
            guard let vrcode = bed.vrcode, !vrcode.isEmpty else {
                events.append(VitalDBRelationshipEventRecord(
                    id: Self.eventID(.unlinkedBed, observedAt, bed.bedID, nil, nil),
                    observedAt: observedAt,
                    eventType: .unlinkedBed,
                    severity: .warning,
                    bedID: bed.bedID,
                    bedName: bed.name,
                    vrcode: nil,
                    previousVrcode: nil,
                    previousBedID: nil,
                    message: "Bed has no linked VRecorder."
                ))
                continue
            }

            if let recorder = recordersByVrcode[vrcode],
               bed.online != recorder.online {
                events.append(VitalDBRelationshipEventRecord(
                    id: Self.eventID(.staleLink, observedAt, bed.bedID, vrcode, nil),
                    observedAt: observedAt,
                    eventType: .staleLink,
                    severity: .warning,
                    bedID: bed.bedID,
                    bedName: bed.name,
                    vrcode: vrcode,
                    previousVrcode: nil,
                    previousBedID: nil,
                    message: "Bed and VRecorder online state differ."
                ))
            }
        }

        for (vrcode, pairs) in bedsByVrcode where pairs.count > 1 {
            let bedIDs = pairs.map(\.1.bedID).sorted()
            events.append(VitalDBRelationshipEventRecord(
                id: Self.eventID(.duplicateAssignment, observedAt, bedIDs.joined(separator: ","), vrcode, nil),
                observedAt: observedAt,
                eventType: .duplicateAssignment,
                severity: .warning,
                bedID: bedIDs.first,
                bedName: nil,
                vrcode: vrcode,
                previousVrcode: nil,
                previousBedID: nil,
                message: "VRecorder is linked to multiple beds: \(bedIDs.joined(separator: ", "))."
            ))
        }

        for recorder in observation.recorders where !linkedBedVrcodes.contains(recorder.vrcode) {
            events.append(VitalDBRelationshipEventRecord(
                id: Self.eventID(.unlinkedRecorder, observedAt, nil, recorder.vrcode, nil),
                observedAt: observedAt,
                eventType: .unlinkedRecorder,
                severity: recorder.online ? .warning : .info,
                bedID: nil,
                bedName: nil,
                vrcode: recorder.vrcode,
                previousVrcode: nil,
                previousBedID: nil,
                message: "VRecorder has no linked bed."
            ))
        }

        return events
    }

    public static func eventID(
        _ eventType: VitalDBRelationshipEventType,
        _ observedAt: String,
        _ bedID: String?,
        _ vrcode: String?,
        _ previous: String?
    ) -> String {
        [
            "relationship",
            eventType.rawValue,
            observedAt,
            bedID ?? "-",
            vrcode ?? "-",
            previous ?? "-",
        ].joined(separator: ":")
    }

    private func insertCommand(
        for bed: VitalDBBedObservation,
        vrcode: String,
        observedAt: String
    ) -> VitalDBBedAssignmentInsertCommand {
        VitalDBBedAssignmentInsertCommand(
            assignmentID: "assignment:\(bed.bedID):\(vrcode):\(observedAt)",
            bedID: bed.bedID,
            bedName: bed.name,
            vrcode: vrcode,
            startedAt: observedAt,
            lastSeenAt: bed.lastSeenAt,
            lastObservedAt: observedAt,
            status: bed.online ? .online : .stale,
            patientConnected: bed.patientConnected
        )
    }
}
