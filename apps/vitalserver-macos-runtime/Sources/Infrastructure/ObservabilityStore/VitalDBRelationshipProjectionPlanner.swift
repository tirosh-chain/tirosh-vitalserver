import Contracts
import Foundation

public struct VitalDBRelationshipProjectionPlanner {
    public init() {}

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

    static func eventID(
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
}
