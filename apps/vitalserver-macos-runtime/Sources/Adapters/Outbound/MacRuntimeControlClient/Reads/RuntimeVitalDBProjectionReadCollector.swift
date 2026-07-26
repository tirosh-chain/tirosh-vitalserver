import Contracts
import RuntimeControl

struct RuntimeVitalDBProjectionReadCollector {
    let repository: RuntimeVitalDBObservationProjectionReading
    let currentObservationProvider: RuntimeVitalDBCurrentObservationProvider

    func observationSnapshotReads() -> (
        current: RuntimeVitalDBCurrentObservationRead,
        projected: RuntimeVitalDBProjectedObservationRead
    ) {
        (
            current: currentObservationProvider.load(),
            projected: projectedObservationRead()
        )
    }

    func recorderProjectionReads(includeActivityBuckets: Bool = true) -> RuntimeVitalDBRecorderProjectionReads {
        RuntimeVitalDBRecorderProjectionReads(
            observations: observationListRead(),
            currentObservation: currentObservationProvider.load(),
            activityBuckets: recorderActivityBucketListRead(includeActivityBuckets: includeActivityBuckets)
        )
    }

    func recorderActivityBucketListRead(
        includeActivityBuckets: Bool
    ) -> RuntimeVitalDBRecorderActivityBucketListRead {
        includeActivityBuckets ? loadRecorderActivityBucketListRead() : .notLoaded
    }

    func relationshipProjectionReads() -> RuntimeVitalDBRelationshipProjectionReads {
        RuntimeVitalDBRelationshipProjectionReads(
            assignments: bedAssignmentListRead(),
            events: relationshipEventListRead()
        )
    }

    private func projectedObservationRead() -> RuntimeVitalDBProjectedObservationRead {
        do {
            return .loaded(try repository.loadLatestObservation())
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func observationListRead() -> RuntimeVitalDBObservationListRead {
        do {
            return .loaded(try repository.loadObservations())
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func loadRecorderActivityBucketListRead() -> RuntimeVitalDBRecorderActivityBucketListRead {
        do {
            return .loaded(try repository.loadRecorderActivityBuckets())
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func bedAssignmentListRead() -> RuntimeVitalDBBedAssignmentListRead {
        do {
            return .loaded(try repository.loadBedAssignments())
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func relationshipEventListRead() -> RuntimeVitalDBRelationshipEventListRead {
        do {
            return .loaded(try repository.loadRelationshipEvents())
        } catch {
            return .failed(String(describing: error))
        }
    }
}
