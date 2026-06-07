@testable import OutboundAdapters
import Contracts
import RuntimeControl
import XCTest

final class RuntimeVitalDBProjectionReadCollectorTests: XCTestCase {
    func testSnapshotReadsPreserveCurrentObservationAndProjectionFailureSeparately() {
        let current = VitalDBObservationDocument(
            observedAt: "2026-06-01T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
        let collector = RuntimeVitalDBProjectionReadCollector(
            repository: ProjectionRepositoryStub(
                latestObservationError: ProjectionRepositoryStubError("latest denied")
            ),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(current, source: .guestRuntimeState)
            }
        )

        let reads = collector.observationSnapshotReads()

        XCTAssertEqual(reads.current.observation, current)
        XCTAssertEqual(reads.current.source, .guestRuntimeState)
        XCTAssertEqual(reads.projected, .failed("latest denied"))
    }

    func testRecorderProjectionReadsPreserveObservationAndActivityFailures() {
        let current = VitalDBObservationDocument(
            observedAt: "2026-06-01T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
        let collector = RuntimeVitalDBProjectionReadCollector(
            repository: ProjectionRepositoryStub(
                observationsError: ProjectionRepositoryStubError("observations denied"),
                activityBucketsError: ProjectionRepositoryStubError("activity denied")
            ),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(current, source: .runtimeStatus)
            }
        )

        let reads = collector.recorderProjectionReads()

        XCTAssertEqual(reads.observations, .failed("observations denied"))
        XCTAssertEqual(reads.currentObservation.observation, current)
        XCTAssertEqual(reads.activityBuckets, .failed("activity denied"))
    }

    func testRelationshipProjectionReadsPreservePartialFailure() {
        let assignment = VitalDBBedAssignmentRecord(
            id: "assignment-1",
            bedID: "bed-a",
            bedName: "A",
            vrcode: "VR_A",
            startedAt: "2026-06-01T00:00:00Z",
            endedAt: nil,
            lastSeenAt: "2026-06-01T00:00:00Z",
            lastObservedAt: "2026-06-01T00:00:00Z",
            status: .online,
            patientConnected: true,
            observationCount: 1
        )
        let collector = RuntimeVitalDBProjectionReadCollector(
            repository: ProjectionRepositoryStub(
                assignments: [assignment],
                relationshipEventsError: ProjectionRepositoryStubError("events denied")
            ),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable()
            }
        )

        let reads = collector.relationshipProjectionReads()

        XCTAssertEqual(reads.assignments, .loaded([assignment]))
        XCTAssertEqual(reads.events, .failed("events denied"))
    }
}

private struct ProjectionRepositoryStubError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct ProjectionRepositoryStub: RuntimeVitalDBObservationProjectionReading {
    var latestObservation: VitalDBObservationDocument?
    var latestObservationError: Error?
    var observations: [VitalDBObservationDocument] = []
    var observationsError: Error?
    var activityBuckets: [VitalDBRecorderActivityBucketRecord] = []
    var activityBucketsError: Error?
    var assignments: [VitalDBBedAssignmentRecord] = []
    var assignmentsError: Error?
    var relationshipEvents: [VitalDBRelationshipEventRecord] = []
    var relationshipEventsError: Error?

    func loadLatestObservation() throws -> VitalDBObservationDocument? {
        if let latestObservationError {
            throw latestObservationError
        }
        return latestObservation
    }

    func loadObservations(limit: Int) throws -> [VitalDBObservationDocument] {
        if let observationsError {
            throw observationsError
        }
        return observations
    }

    func loadRecorderActivityBuckets(query: VitalDBRecorderActivityBucketQuery) throws -> [VitalDBRecorderActivityBucketRecord] {
        if let activityBucketsError {
            throw activityBucketsError
        }
        return activityBuckets
    }

    func loadBedAssignments(limit: Int) throws -> [VitalDBBedAssignmentRecord] {
        if let assignmentsError {
            throw assignmentsError
        }
        return assignments
    }

    func loadRelationshipEvents(limit: Int) throws -> [VitalDBRelationshipEventRecord] {
        if let relationshipEventsError {
            throw relationshipEventsError
        }
        return relationshipEvents
    }
}
