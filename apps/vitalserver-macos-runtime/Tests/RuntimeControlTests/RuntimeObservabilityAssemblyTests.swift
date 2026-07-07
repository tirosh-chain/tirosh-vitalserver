import Contracts
import RuntimeControl
import XCTest

final class RuntimeObservabilityAssemblyTests: XCTestCase {
    func testObservationSnapshotAssemblerPrefersCurrentObservationAndPreservesProjectionFailure() {
        let currentObservation = observation("2026-06-01T00:00:10Z", vrcode: "VR_CURRENT")
        let snapshot = RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: .loaded(
                currentObservation,
                source: .guestControlAPI,
                readIssues: ["guestControl=stale-before-current-read"]
            ),
            projectedObservation: .failed("sqlite projection unavailable")
        )

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-06-01T00:00:10Z")
        XCTAssertEqual(
            snapshot.readError,
            "projection=sqlite projection unavailable;guestControl=stale-before-current-read"
        )
    }

    func testObservationSnapshotAssemblerUsesProjectionWhenCurrentObservationIsUnavailable() {
        let projectedObservation = observation("2026-06-01T00:00:01Z", vrcode: "VR_PROJECTED")
        let snapshot = RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: .unavailable(readIssues: ["guestControl=missing"]),
            projectedObservation: .loaded(projectedObservation)
        )

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-06-01T00:00:01Z")
        XCTAssertEqual(snapshot.readError, "guestControl=missing")
    }

    func testRecorderHistoryAssemblerPreservesObservationAndActivityProjectionFailuresWithCurrentObservation() {
        let currentObservation = observation("2026-06-01T00:00:10Z", vrcode: "VR_CURRENT")
        let history = RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: RuntimeVitalDBRecorderProjectionReads(
                observations: .failed("observations unavailable"),
                currentObservation: .loaded(
                    currentObservation,
                    source: .guestControlAPI,
                    readIssues: ["guestControl=missing"]
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
            "observations=observations unavailable;currentObservation=guestControl=missing;activityBuckets=activity unavailable"
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
                    source: .guestControlAPI,
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

    func testRecorderHistoryAssemblerUsesExplicitRecorderIngressStatusReadWithoutOverridingVitalDBState() {
        let currentObservation = VitalDBObservationDocument(
            observedAt: "2026-06-01T00:00:10Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_CURRENT",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-06-01T00:00:00Z",
                    online: true,
                    stale: true
                ),
            ]
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_CURRENT",
                        activeConnections: 1,
                        selectedIp: "192.168.64.20",
                        ipSource: "x-forwarded-for",
                        lastSeenAt: "2026-06-01T00:00:09Z"
                    ),
                ]
            ),
            readError: nil
        )

        let history = RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: RuntimeVitalDBRecorderProjectionReads(
                observations: .loaded([]),
                currentObservation: .loaded(
                    currentObservation,
                    source: .guestControlAPI,
                    readIssues: []
                ),
                activityBuckets: .notLoaded
            ),
            recorderIngressStatusRead: ingressRead
        )

        XCTAssertEqual(history.recorders.first?.status, .stale)
        XCTAssertEqual(history.recorders.first?.lastSeenAt, "2026-06-01T00:00:00Z")
        XCTAssertEqual(history.recorderIngressStatusRead?.readState, .loaded)
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.summary.staleRecorders, 1)
    }

    func testRecorderActivityWindowAssemblerFillsOnlyRequestedAllPage() {
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_A",
            bucketSeconds: 60,
            period: .all,
            pageIndex: 4
        )
        let bounds = VitalDBRecorderActivityBucketBounds(
            vrcode: "VR_A",
            firstBucketStartedAt: "2026-01-01T00:00:00Z",
            latestBucketStartedAt: "2026-01-02T00:00:00Z"
        )
        let records = [
            VitalDBRecorderActivityBucketRecord(
                vrcode: "VR_A",
                bucketStartedAt: "2026-01-02T00:00:00Z",
                bucketSeconds: 60,
                messageCount: 5,
                byteCount: 50,
                roomCount: 1,
                firstObservedAt: "2026-01-02T00:00:01Z",
                lastObservedAt: "2026-01-02T00:00:02Z"
            ),
        ]

        let window = RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: bounds,
            records: records
        )

        XCTAssertEqual(window.state, .loaded)
        XCTAssertEqual(window.page.index, 4)
        XCTAssertEqual(window.page.count, 5)
        XCTAssertEqual(window.page.windowStartedAt, "2026-01-01T12:01:00Z")
        XCTAssertEqual(window.page.windowEndedAt, "2026-01-02T00:01:00Z")
        XCTAssertEqual(window.buckets.count, 720)
        XCTAssertEqual(window.buckets.last?.messageCount, 5)
    }

    func testRecorderActivityWindowReadQueryUsesSelectedPageBounds() throws {
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_A",
            bucketSeconds: 300,
            period: .all,
            pageIndex: 4
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
        XCTAssertEqual(readQuery.since, "2026-01-01T12:05:00Z")
        XCTAssertEqual(readQuery.until, "2026-01-02T00:05:00Z")
        XCTAssertEqual(readQuery.limit, 2000)
    }

    func testRecorderActivityWindowUsesCurrentTimeForRecentPeriods() throws {
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_A",
            bucketSeconds: 60,
            period: .lastHour
        )
        let bounds = VitalDBRecorderActivityBucketBounds(
            vrcode: "VR_A",
            firstBucketStartedAt: "2026-01-01T00:00:00Z",
            latestBucketStartedAt: "2026-01-01T00:40:00Z"
        )
        let currentTime = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T01:00:10Z"))

        let readQuery = try XCTUnwrap(RuntimeVitalRecorderActivityWindowAssembler.windowReadQuery(
            query: query,
            bounds: bounds,
            currentTime: currentTime
        ))
        let window = RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: bounds,
            records: [
                VitalDBRecorderActivityBucketRecord(
                    vrcode: "VR_A",
                    bucketStartedAt: "2026-01-01T00:40:00Z",
                    bucketSeconds: 60,
                    messageCount: 5,
                    byteCount: 50,
                    roomCount: 1,
                    firstObservedAt: "2026-01-01T00:40:01Z",
                    lastObservedAt: "2026-01-01T00:40:02Z"
                ),
            ],
            currentTime: currentTime
        )

        XCTAssertEqual(readQuery.since, "2026-01-01T00:01:00Z")
        XCTAssertEqual(readQuery.until, "2026-01-01T01:01:00Z")
        XCTAssertEqual(window.page.windowStartedAt, "2026-01-01T00:01:00Z")
        XCTAssertEqual(window.page.windowEndedAt, "2026-01-01T01:01:00Z")
        XCTAssertEqual(window.buckets.count, 60)
        XCTAssertEqual(window.buckets.first?.messageCount, 0)
        XCTAssertEqual(window.buckets.first(where: { $0.bucketStartedAt == "2026-01-01T00:40:00Z" })?.messageCount, 5)
        XCTAssertEqual(window.buckets.last?.bucketStartedAt, "2026-01-01T01:00:00Z")
        XCTAssertEqual(window.buckets.last?.messageCount, 0)
    }

    func testRecorderActivityWindowAssemblerFillsZerosFromInitialConnectionBound() {
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_A",
            bucketSeconds: 60,
            period: .all,
            pageIndex: 0
        )
        let bounds = VitalDBRecorderActivityBucketBounds(
            vrcode: "VR_A",
            firstBucketStartedAt: "2026-05-25T00:00:00Z",
            latestBucketStartedAt: "2026-05-25T00:03:00Z"
        )
        let records = [
            VitalDBRecorderActivityBucketRecord(
                vrcode: "VR_A",
                bucketStartedAt: "2026-05-25T00:02:00Z",
                bucketSeconds: 60,
                messageCount: 3,
                byteCount: 900,
                roomCount: 1,
                firstObservedAt: "2026-05-25T00:02:05Z",
                lastObservedAt: "2026-05-25T00:02:05Z"
            ),
        ]

        let window = RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: bounds,
            records: records
        )

        XCTAssertEqual(window.buckets.map(\.bucketStartedAt), [
            "2026-05-25T00:00:00Z",
            "2026-05-25T00:01:00Z",
            "2026-05-25T00:02:00Z",
            "2026-05-25T00:03:00Z",
        ])
        XCTAssertEqual(window.buckets.map(\.messageCount), [0, 0, 3, 0])
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
