import Contracts
import Domain

public struct PlanVitalDBRelationshipProjectionUseCase {
    public init() {}

    public func projectionPlan(
        for observation: VitalDBObservationDocument,
        openAssignmentsByBedID: [String: VitalDBBedAssignmentRecord]
    ) -> VitalDBRelationshipProjectionPlan {
        VitalDBRelationshipProjectionPlanner().projectionPlan(
            for: observation,
            openAssignmentsByBedID: openAssignmentsByBedID
        )
    }

    public func plannedEvents(for observation: VitalDBObservationDocument) -> [VitalDBRelationshipEventRecord] {
        VitalDBRelationshipProjectionPlanner().plannedEvents(for: observation)
    }
}
