import Contracts
import RuntimeControl

struct RuntimeVitalRelationshipPresentationHistory {
    let assignments: [RuntimeVitalBedAssignmentRecord]
    let events: [RuntimeVitalRelationshipEventRecord]
}

struct RuntimeVitalRelationshipPresentationIndex {
    private let bedAssignments: [String: [RuntimeVitalBedAssignmentRecord]]
    private let bedEvents: [String: [RuntimeVitalRelationshipEventRecord]]
    private let recorderAssignments: [String: [RuntimeVitalBedAssignmentRecord]]
    private let recorderEvents: [String: [RuntimeVitalRelationshipEventRecord]]

    init(
        history: RuntimeVitalRelationshipHistory = RuntimeVitalRelationshipHistory(),
        itemLimit: Int = 8
    ) {
        precondition(itemLimit > 0)
        bedAssignments = Self.index(
            history.assignments,
            keys: { [$0.bedID] },
            itemLimit: itemLimit
        )
        bedEvents = Self.index(
            history.events,
            keys: { event in event.bedID.map { [$0] } ?? [] },
            itemLimit: itemLimit
        )
        recorderAssignments = Self.index(
            history.assignments,
            keys: { [$0.vrcode] },
            itemLimit: itemLimit
        )
        recorderEvents = Self.index(
            history.events,
            keys: { event in
                Array(Set([event.vrcode, event.previousVrcode].compactMap { $0 }))
            },
            itemLimit: itemLimit
        )
    }

    func history(bedID: String) -> RuntimeVitalRelationshipPresentationHistory {
        RuntimeVitalRelationshipPresentationHistory(
            assignments: bedAssignments[bedID] ?? [],
            events: bedEvents[bedID] ?? []
        )
    }

    func history(vrcode: String) -> RuntimeVitalRelationshipPresentationHistory {
        RuntimeVitalRelationshipPresentationHistory(
            assignments: recorderAssignments[vrcode] ?? [],
            events: recorderEvents[vrcode] ?? []
        )
    }

    private static func index<Value>(
        _ values: [Value],
        keys: (Value) -> [String],
        itemLimit: Int
    ) -> [String: [Value]] {
        var result: [String: [Value]] = [:]
        for value in values {
            for key in keys(value) where result[key, default: []].count < itemLimit {
                result[key, default: []].append(value)
            }
        }
        return result
    }
}
