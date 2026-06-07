import Contracts

protocol RuntimeVitalDBObservationProjectionReading {
    func loadLatestObservation() throws -> VitalDBObservationDocument?
    func loadObservations(limit: Int) throws -> [VitalDBObservationDocument]
    func loadRecorderActivityBuckets(query: VitalDBRecorderActivityBucketQuery) throws -> [VitalDBRecorderActivityBucketRecord]
    func loadBedAssignments(limit: Int) throws -> [VitalDBBedAssignmentRecord]
    func loadRelationshipEvents(limit: Int) throws -> [VitalDBRelationshipEventRecord]
}

extension RuntimeVitalDBObservationProjectionReading {
    func loadObservations() throws -> [VitalDBObservationDocument] {
        try loadObservations(limit: 1000)
    }

    func loadRecorderActivityBuckets() throws -> [VitalDBRecorderActivityBucketRecord] {
        try loadRecorderActivityBuckets(query: VitalDBRecorderActivityBucketQuery())
    }

    func loadBedAssignments() throws -> [VitalDBBedAssignmentRecord] {
        try loadBedAssignments(limit: 1000)
    }

    func loadRelationshipEvents() throws -> [VitalDBRelationshipEventRecord] {
        try loadRelationshipEvents(limit: 1000)
    }
}

extension SQLiteVitalDBObservationRepository: RuntimeVitalDBObservationProjectionReading {}
