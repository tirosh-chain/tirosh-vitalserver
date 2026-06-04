import Contracts
import Foundation

public struct SQLiteVitalDBObservationRepository {
    private let store: SQLiteRuntimeObservabilityStore

    public init(url: URL) {
        self.store = SQLiteRuntimeObservabilityStore(url: url)
    }

    public init(store: SQLiteRuntimeObservabilityStore) {
        self.store = store
    }

    public func append(_ observation: VitalDBObservationDocument) throws {
        try store.append(observation)
    }

    public func loadLatestObservation() throws -> VitalDBObservationDocument? {
        try store.loadLatestVitalDBObservation()
    }

    public func loadObservations(limit: Int = 1000) throws -> [VitalDBObservationDocument] {
        try store.loadVitalDBObservations(limit: limit)
    }

    public func loadRecorderActivityBuckets(
        query: VitalDBRecorderActivityBucketQuery = VitalDBRecorderActivityBucketQuery()
    ) throws -> [VitalDBRecorderActivityBucketRecord] {
        try store.loadVitalDBRecorderActivityBuckets(query: query)
    }

    public func loadBedAssignments(limit: Int = 1000) throws -> [VitalDBBedAssignmentRecord] {
        try store.loadVitalDBBedAssignments(limit: limit)
    }

    public func loadRelationshipEvents(limit: Int = 1000) throws -> [VitalDBRelationshipEventRecord] {
        try store.loadVitalDBRelationshipEvents(limit: limit)
    }
}
