import Contracts
import Errors

extension SQLiteRuntimeObservabilityStore {
    private var relationshipQueries: SQLiteVitalDBRelationshipQueries {
        SQLiteVitalDBRelationshipQueries()
    }

    public func loadVitalDBBedAssignments(limit: Int = 1000) throws -> [VitalDBBedAssignmentRecord] {
        guard limit > 0 else {
            return []
        }
        return try database.withReadOnlyDatabase { db in
            try relationshipQueries.loadBedAssignments(db, limit: limit)
        }
    }

    public func loadVitalDBRelationshipEvents(limit: Int = 1000) throws -> [VitalDBRelationshipEventRecord] {
        guard limit > 0 else {
            return []
        }
        return try database.withReadOnlyDatabase { db in
            try relationshipQueries.loadRelationshipEvents(db, limit: limit)
        }
    }

    func projectRelationships(
        _ observation: VitalDBObservationDocument,
        db: OpaquePointer
    ) throws {
        guard let relationshipProjectionPlanner else {
            throw SQLiteRuntimeObservabilityStoreError.relationshipProjectionProviderMissing
        }
        try SQLiteVitalDBRelationshipProjectionWriter(
            relationshipProjectionPlanner: relationshipProjectionPlanner
        ).projectRelationships(observation, db: db)
    }
}
