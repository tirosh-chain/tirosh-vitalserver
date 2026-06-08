import Contracts
import RuntimeControl
import XCTest

final class RuntimeObservabilityAssemblyTests: XCTestCase {
    func testObservationSnapshotAssemblerPrefersCurrentObservationAndPreservesProjectionFailure() {
        let currentObservation = observation("2026-06-01T00:00:10Z", vrcode: "VR_CURRENT")
        let snapshot = RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: .loaded(
                currentObservation,
                source: .guestRuntimeState,
                readIssues: ["runtimeState=stale-before-current-read"]
            ),
            projectedObservation: .failed("sqlite projection unavailable")
        )

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-06-01T00:00:10Z")
        XCTAssertEqual(
            snapshot.readError,
            "projection=sqlite projection unavailable;runtimeState=stale-before-current-read"
        )
    }

    func testObservationSnapshotAssemblerUsesProjectionWhenCurrentObservationIsUnavailable() {
        let projectedObservation = observation("2026-06-01T00:00:01Z", vrcode: "VR_PROJECTED")
        let snapshot = RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: .unavailable(readIssues: ["runtimeState=missing", "runtimeStatus=missing"]),
            projectedObservation: .loaded(projectedObservation)
        )

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-06-01T00:00:01Z")
        XCTAssertEqual(snapshot.readError, "runtimeState=missing;runtimeStatus=missing")
    }

    func testRecorderHistoryAssemblerPreservesObservationAndActivityProjectionFailuresWithCurrentObservation() {
        let currentObservation = observation("2026-06-01T00:00:10Z", vrcode: "VR_CURRENT")
        let history = RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: RuntimeVitalDBRecorderProjectionReads(
                observations: .failed("observations unavailable"),
                currentObservation: .loaded(
                    currentObservation,
                    source: .runtimeStatus,
                    readIssues: ["runtimeState=missing"]
                ),
                activityBuckets: .failed("activity unavailable")
            )
        )

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.updatedAt, "2026-06-01T00:00:10Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_CURRENT"])
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertEqual(
            history.readError,
            "observations=observations unavailable;currentObservation=runtimeState=missing;activityBuckets=activity unavailable"
        )
        XCTAssertEqual(history.activityHistory.readError, history.readError)
    }

    func testRecorderHistoryAssemblerKeepsActivityNotLoadedDistinctFromFailure() {
        let currentObservation = observation("2026-06-01T00:00:10Z", vrcode: "VR_CURRENT")
        let history = RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: RuntimeVitalDBRecorderProjectionReads(
                observations: .loaded([]),
                currentObservation: .loaded(
                    currentObservation,
                    source: .runtimeStatus,
                    readIssues: []
                ),
                activityBuckets: .notLoaded
            )
        )

        XCTAssertEqual(history.state, .loaded)
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_CURRENT"])
        XCTAssertNil(history.recorders.first?.activityTimeline)
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertNil(history.readError)
    }

    func testRecorderActivityWindowAssemblerFillsOnlyRequestedAllPage() {
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_A",
            bucketSeconds: 60,
            period: .all,
            pageIndex: 1
        )
        let bounds = VitalDBRecorderActivityBucketBounds(
            vrcode: "VR_A",
            firstBucketStartedAt: "2026-01-01T00:00:00Z",
            latestBucketStartedAt: "2026-01-02T00:00:00Z"
        )
        let records = [
            VitalDBRecorderActivityBucketRecord(
                vrcode: "VR_A",
                bucketStartedAt: "2026-01-01T23:59:00Z",
                bucketSeconds: 60,
                messageCount: 5,
                byteCount: 50,
                roomCount: 1,
                firstObservedAt: "2026-01-01T23:59:01Z",
                lastObservedAt: "2026-01-01T23:59:02Z"
            ),
        ]

        let window = RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: bounds,
            records: records
        )

        XCTAssertEqual(window.state, .loaded)
        XCTAssertEqual(window.page.index, 1)
        XCTAssertEqual(window.page.count, 3)
        XCTAssertEqual(window.page.windowStartedAt, "2026-01-01T12:00:00Z")
        XCTAssertEqual(window.page.windowEndedAt, "2026-01-02T00:00:00Z")
        XCTAssertEqual(window.buckets.count, 720)
        XCTAssertEqual(window.buckets.last?.messageCount, 5)
    }

    func testRecorderActivityWindowReadQueryUsesSelectedPageBounds() throws {
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_A",
            bucketSeconds: 300,
            period: .all,
            pageIndex: 1
        )
        let bounds = VitalDBRecorderActivityBucketBounds(
            vrcode: "VR_A",
            firstBucketStartedAt: "2026-01-01T00:00:00Z",
            latestBucketStartedAt: "2026-01-02T00:00:00Z"
        )

        let readQuery = try XCTUnwrap(RuntimeVitalRecorderActivityWindowAssembler.windowReadQuery(
            query: query,
            bounds: bounds
        ))

        XCTAssertEqual(readQuery.vrcode, "VR_A")
        XCTAssertEqual(readQuery.since, "2026-01-01T12:00:00Z")
        XCTAssertEqual(readQuery.until, "2026-01-02T00:00:00Z")
        XCTAssertEqual(readQuery.limit, 2000)
    }

    func testRelationshipHistoryAssemblerMapsLoadedAssignmentsAndPreservesPartialReadFailure() {
        let history = RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
            reads: RuntimeVitalDBRelationshipProjectionReads(
                assignments: .loaded([
                    VitalDBBedAssignmentRecord(
                        id: "assignment-1",
                        bedID: "bed-a",
                        bedName: "A",
                        vrcode: "VR_A",
                        startedAt: "2026-06-01T00:00:00Z",
                        endedAt: nil,
                        lastSeenAt: "2026-06-01T00:00:05Z",
                        lastObservedAt: "2026-06-01T00:00:10Z",
                        status: .online,
                        patientConnected: true,
                        observationCount: 2
                    ),
                ]),
                events: .failed("events unavailable")
            )
        )

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.assignments.map(\.assignmentID), ["assignment-1"])
        XCTAssertEqual(history.assignments.first?.status, .online)
        XCTAssertTrue(history.events.isEmpty)
        XCTAssertEqual(history.readError, "events=events unavailable")
    }

    private func observation(
        _ observedAt: String,
        vrcode: String
    ) -> VitalDBObservationDocument {
        VitalDBObservationDocument(
            observedAt: observedAt,
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: vrcode,
                    lastSeenAt: observedAt,
                    online: true
                ),
            ]
        )
    }
}
