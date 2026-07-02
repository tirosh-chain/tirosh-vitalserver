import Contracts
import Application
import OutboundAdapters
@testable import OutboundAdapters
import RuntimeControl
import SQLite3
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeObservabilityReaderTests: XCTestCase {
    func testProtocolRequiresExplicitObservationSnapshot() {
        let reader = DefaultSnapshotObservabilityReader(snapshot: .loaded(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:00Z")
    }

    func testLoadRuntimeEventsLimitDelegatesToQueryReader() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let runtimeEvents = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let event = runtimeEvent(id: "event-limit", timestamp: "2026-05-31T00:00:00Z")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try (encoder.encode(event) + Data("\n".utf8)).write(to: runtimeEvents)
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeEvents: runtimeEvents.path,
                runtimeObservabilityDB: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB).path
            )
        )

        let history = reader.loadRuntimeEvents(limit: 5)

        XCTAssertEqual(history.events.map(\.id), ["event-limit"])
        XCTAssertEqual(history.matchingCount, 1)
    }

    func testLoadRuntimeEventsReportsReadFailedWhenNoEventSourceCanBeRead() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeEvents: directory.appendingPathComponent(RuntimeFileNames.runtimeEvents).path,
                runtimeObservabilityDB: "/dev/null/events.sqlite"
            )
        )

        let history = reader.loadRuntimeEvents(query: RuntimeEventQuery(limit: 10))

        XCTAssertEqual(history.state, .readFailed)
        XCTAssertEqual(history.events, [])
        XCTAssertNotNil(history.readError)
    }

    func testProductObservationSnapshotDoesNotReadHostSQLiteProjection() {
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable(readIssues: ["guestControl=unavailable"])
            }
        )

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertEqual(snapshot.observation, nil)
        XCTAssertEqual(snapshot.readError, "guestControl=unavailable")
    }

    func testProductReadsReportGuestReadModelUnavailableWithoutHostSQLiteFallback() {
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable(readIssues: ["guestControl=unavailable"])
            }
        )

        let snapshot = reader.loadVitalDBObservationSnapshot()
        let history = reader.loadVitalDBRecorders()
        let relationships = reader.loadVitalDBRelationships()
        let window = reader.loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_DISABLED",
            bucketSeconds: 60,
            period: .all,
            pageIndex: 0
        ))

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertEqual(snapshot.readError, "guestControl=unavailable")
        XCTAssertEqual(history.state, .readFailed)
        XCTAssertEqual(history.readError, "currentObservation=guestControl=unavailable")
        XCTAssertEqual(relationships.state, .readFailed)
        XCTAssertEqual(relationships.readError, "Guest VitalDB relationship read model is unavailable.")
        XCTAssertEqual(window.state, .readFailed)
        XCTAssertEqual(window.readError, "Guest VitalDB activity read model is unavailable.")
    }

    func testLiveCurrentObservationProviderReadsGuestControlAPI() {
        let provider = RuntimeVitalDBCurrentObservationProvider.live(
            paths: RuntimePaths(),
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { _ in
                GuestVitalDBObservationGatewayStub(
                    read: RuntimeGuestControlVitalDBObservationRead(
                        state: .loaded,
                        observation: VitalDBObservationDocument(
                            observedAt: "2026-07-01T00:00:00+00:00",
                            ready: true,
                            recorderOnlineThresholdSeconds: 60
                        ),
                        readError: nil
                    )
                )
            }
        )

        let read = provider.load()

        XCTAssertEqual(read.source, .guestControlAPI)
        XCTAssertEqual(read.observation?.observedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(read.readIssues, [])
    }

    func testLiveCurrentObservationProviderPreservesGuestControlUnavailableRead() {
        let provider = RuntimeVitalDBCurrentObservationProvider.live(
            paths: RuntimePaths(),
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { _ in
                GuestVitalDBObservationGatewayStub(
                    read: RuntimeGuestControlVitalDBObservationRead(
                        state: .unavailable,
                        observation: nil,
                        readError: "VitalDB observation read model is empty."
                    )
                )
            }
        )

        let read = provider.load()

        XCTAssertNil(read.source)
        XCTAssertNil(read.observation)
        XCTAssertEqual(
            read.readIssues,
            ["guestControl=VitalDB observation read model is empty."]
        )
    }

    func testLiveGuestReadModelProviderBuildsObservationFromRecordersAndBeds() {
        let provider = RuntimeVitalDBGuestReadModelProvider.live(
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { _ in
                GuestVitalDBObservationGatewayStub(
                    read: RuntimeGuestControlVitalDBObservationRead(state: .unavailable),
                    recorderRead: RuntimeGuestControlVitalDBRecorderRead(
                        state: .loaded,
                        recorders: [
                            VitalDBRecorderObservation(vrcode: "VR_GUEST", online: true),
                        ],
                        observedAt: "2026-07-01T00:00:00+00:00",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60
                    ),
                    bedRead: RuntimeGuestControlVitalDBBedRead(
                        state: .loaded,
                        beds: [
                            VitalDBBedObservation(
                                bedID: "bed-a",
                                name: "OR-A",
                                vrcode: "VR_GUEST",
                                online: true
                            ),
                        ],
                        observedAt: "2026-07-01T00:00:00+00:00",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60
                    )
                )
            }
        )

        let read = provider.load()

        XCTAssertEqual(read.source, .guestControlAPI)
        XCTAssertEqual(read.observation?.source, "guest-control-api")
        XCTAssertEqual(read.observation?.recorders.map(\.vrcode), ["VR_GUEST"])
        XCTAssertEqual(read.observation?.beds.map(\.bedID), ["bed-a"])
        XCTAssertEqual(read.readIssues, [])
    }

    func testLiveGuestReadModelProviderRejectsMismatchedReadMetadata() {
        let provider = RuntimeVitalDBGuestReadModelProvider.live(
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { _ in
                GuestVitalDBObservationGatewayStub(
                    read: RuntimeGuestControlVitalDBObservationRead(state: .unavailable),
                    recorderRead: RuntimeGuestControlVitalDBRecorderRead(
                        state: .loaded,
                        observedAt: "2026-07-01T00:00:00+00:00",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60
                    ),
                    bedRead: RuntimeGuestControlVitalDBBedRead(
                        state: .loaded,
                        observedAt: "2026-07-01T00:00:01+00:00",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60
                    )
                )
            }
        )

        let read = provider.load()

        XCTAssertNil(read.observation)
        XCTAssertTrue(read.readIssues.contains {
            $0.contains("guestControl=observedAtMismatch")
        })
    }

    func testLoadVitalDBRecordersUsesGuestReadModelBeforeSQLiteProjection() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_SQLITE", online: true),
            ]
        ))
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: database.path),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable()
            },
            guestVitalDBReadModelProvider: RuntimeVitalDBGuestReadModelProvider {
                .loaded(
                    VitalDBObservationDocument(
                        source: "guest-control-api",
                        observedAt: "2026-07-01T00:00:00+00:00",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60,
                        recorders: [
                            VitalDBRecorderObservation(vrcode: "VR_GUEST", online: true),
                        ],
                        beds: [
                            VitalDBBedObservation(
                                bedID: "bed-a",
                                name: "OR-A",
                                vrcode: "VR_GUEST",
                                online: true
                            ),
                        ]
                    ),
                    source: .guestControlAPI
                )
            }
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.state, .loaded)
        XCTAssertEqual(history.updatedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_GUEST"])
        XCTAssertEqual(history.beds.map(\.bedID), ["bed-a"])
    }

    func testLoadVitalDBRecordersDoesNotReadSQLiteProjectionWhenGuestReadModelExists() {
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable()
            },
            guestVitalDBReadModelProvider: RuntimeVitalDBGuestReadModelProvider {
                .loaded(
                    VitalDBObservationDocument(
                        source: "guest-control-api",
                        observedAt: "2026-07-01T00:00:00+00:00",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60,
                        recorders: [
                            VitalDBRecorderObservation(vrcode: "VR_GUEST", online: true),
                        ]
                    ),
                    source: .guestControlAPI
                )
            }
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.recorders.map { $0.vrcode }, ["VR_GUEST"])
        XCTAssertEqual(
            history.activityHistory.source,
            RuntimeVitalRecorderActivityHistorySource.notProvided
        )
        XCTAssertFalse(history.readError?.contains("sqlite observations should not be read") == true)
        XCTAssertFalse(history.readError?.contains("activityBuckets=") == true)
    }

    func testLoadVitalDBObservationSnapshotDoesNotUseGuestRuntimeStateAsCurrentObservation() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", online: true),
            ]
        ))
        try writeRuntimeState(
            to: runtimeState,
            observation: VitalDBObservationDocument(
                observedAt: "2026-05-31T00:00:05Z",
                ready: true,
                recorderOnlineThresholdSeconds: 60,
                recorders: [
                    VitalDBRecorderObservation(vrcode: "VR_A", online: false, stale: true),
                ]
            )
        )
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: runtimeState.path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertTrue(snapshot.readError?.contains("guestControl=") == true)
    }

    func testLoadVitalDBObservationSnapshotDoesNotUseRuntimeStatusAsCurrentObservation() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_PROJECTED", online: true),
            ]
        ))
        try writeLegacyRuntimeStatus(
            to: runtimeStatus,
            observation: VitalDBObservationDocument(
                observedAt: "2026-05-31T00:00:10Z",
                ready: true,
                recorderOnlineThresholdSeconds: 60,
                recorders: [
                    VitalDBRecorderObservation(vrcode: "VR_STATUS", online: true),
                ]
            )
        )
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
            runtimeStatus: runtimeStatus.path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertTrue(snapshot.readError?.contains("guestControl=") == true)
    }

    func testLoadVitalDBObservationSnapshotIgnoresRuntimeStatePathIssues() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        ))
        try FileManager.default.createDirectory(at: runtimeState, withIntermediateDirectories: true)
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: runtimeState.path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertTrue(snapshot.readError?.contains("guestControl=") == true)
    }

    func testLoadVitalDBObservationSnapshotIgnoresRuntimeStatusPathIssues() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        ))
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path,
                runtimeObservabilityDB: database.path
            ),
            fileStore: ObservabilityPathStateFileStore(pathStates: [
                runtimeStatus.path: .inspectFailed("permission denied"),
            ])
        )

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertTrue(snapshot.readError?.contains("guestControl=") == true)
    }

    func testLoadVitalDBObservationReportsMissingCurrentObservationSourcesWhenProjectionIsEmpty() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
            runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertTrue(snapshot.readError?.contains("guestControl=") == true)
    }

    func testDiagnosticsProjectionReaderPreservesProjectionReadFailuresWithStatusProviderFallback() {
        let statusObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_STATUS", online: true),
            ]
        )
        let reader = RuntimeVitalDBHostDiagnosticsProjectionReader(
            mode: .diagnostics,
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            makeVitalDBProjectionRepository: { _ in
                FailingVitalDBProjectionRepository(
                    observationError: ProjectionReadFailure(message: "observations unavailable"),
                    activityError: ProjectionReadFailure(message: "activity unavailable")
                )
            }
        )

        let history = RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: reader.recorderProjectionReads(
                includeActivityBuckets: true,
                currentObservation: .loaded(statusObservation, source: .guestControlAPI)
            )
        )

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.updatedAt, "2026-05-31T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STATUS"])
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertTrue(history.readError?.contains("observations=") == true)
        XCTAssertTrue(history.readError?.contains("activityBuckets=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("observations=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("activityBuckets=") == true)
    }

    func testDiagnosticsProjectionReaderPreservesInjectedPartialProjectionReadFailure() {
        let reader = RuntimeVitalDBHostDiagnosticsProjectionReader(
            mode: .diagnostics,
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            makeVitalDBProjectionRepository: { _ in
                FailingVitalDBProjectionRepository(
                    assignments: [
                        VitalDBBedAssignmentRecord(
                            id: "assignment-1",
                            bedID: "bed-a",
                            bedName: "A",
                            vrcode: "VR_A",
                            startedAt: "2026-05-31T00:00:00Z",
                            endedAt: nil,
                            lastSeenAt: "2026-05-31T00:00:00Z",
                            lastObservedAt: "2026-05-31T00:00:00Z",
                            status: .online,
                            patientConnected: true,
                            observationCount: 1
                        ),
                    ],
                    relationshipEventError: ProjectionReadFailure(message: "events unavailable")
                )
            }
        )

        let history = RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
            reads: reader.relationshipProjectionReads()
        )

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.assignments.map(\.bedID), ["bed-a"])
        XCTAssertEqual(history.events, [])
        XCTAssertTrue(history.readError?.contains("events=") == true)
        XCTAssertTrue(history.readError?.contains("events unavailable") == true)
        XCTAssertFalse(history.readError?.contains("assignments=") == true)
    }

    func testLoadVitalDBRecordersDoesNotUseGuestRuntimeStateOrSQLiteProjectionWhenGuestReadIsUnavailable() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_LIVE",
                    ip: "10.0.0.10",
                    lastSeenAt: "2026-05-31T00:00:00Z",
                    online: true
                ),
            ]
        ))
        try writeRuntimeState(
            to: runtimeState,
            observation: VitalDBObservationDocument(
                observedAt: "2026-05-31T00:00:05Z",
                ready: true,
                recorderOnlineThresholdSeconds: 60,
                recorders: [
                    VitalDBRecorderObservation(
                        vrcode: "VR_LIVE",
                        ip: "10.0.0.10",
                        lastSeenAt: "2026-05-31T00:00:05Z",
                        online: false,
                        stale: true
                    ),
                ]
            )
        )
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: runtimeState.path,
            runtimeObservabilityDB: database.path
        ))

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.state, .readFailed)
        XCTAssertNil(history.updatedAt)
        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertTrue(history.readError?.contains("currentObservation=guestControl=") == true)
    }

    func testLoadVitalDBRecordersReportsCurrentObservationNotProvided() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_PROJECTED", online: true),
            ]
        ))
        try Data("not-json".utf8).write(to: runtimeState)
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: runtimeState.path,
            runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
            runtimeObservabilityDB: database.path
        ))

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.state, .readFailed)
        XCTAssertNil(history.updatedAt)
        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertTrue(history.readError?.contains("currentObservation=guestControl=") == true)
        XCTAssertTrue(
            history.activityHistory.readError?.contains("currentObservation=guestControl=") == true
        )
    }

    func testLoadVitalDBRecordersReturnsNilStatusFallbackWhenStatusFileIsMissing() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                runtimeObservabilityDB: database.path
            )
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.state, .readFailed)
        XCTAssertNil(history.updatedAt)
        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertTrue(history.readError?.contains("currentObservation=guestControl=") == true)
        XCTAssertTrue(
            history.activityHistory.readError?.contains("currentObservation=guestControl=") == true
        )
    }

    func testLoadVitalDBRecordersUsesInjectedRecorderIngressStatusReadProvider() {
        let currentObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:10Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_INGRESS_ONLY",
                        activeConnections: 1,
                        selectedIp: "192.168.64.21",
                        ipSource: "socket",
                        lastSeenAt: "2026-05-31T00:00:09Z"
                    ),
                ]
            ),
            readError: nil
        )
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(currentObservation, source: .guestControlAPI)
            },
            recorderIngressStatusReadProvider: StubRecorderIngressStatusReadProvider(result: ingressRead)
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_INGRESS_ONLY"])
        XCTAssertEqual(history.recorders.first?.lastIP, "192.168.64.21")
        XCTAssertEqual(history.recorders.first?.lastSeenAt, "2026-05-31T00:00:09Z")
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertNil(history.readError)
    }

    func testLoadVitalDBRecorderSummariesUsesInjectedRecorderIngressStatusReadProvider() {
        let currentObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:10Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                activeRecorderConnections: 1,
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_SUMMARY",
                        activeConnections: 1,
                        selectedIp: "192.168.64.22",
                        lastSeenAt: "2026-05-31T00:00:08Z"
                    ),
                ]
            ),
            readError: nil
        )
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(currentObservation, source: .guestControlAPI)
            },
            recorderIngressStatusReadProvider: StubRecorderIngressStatusReadProvider(result: ingressRead)
        )

        let history = reader.loadVitalDBRecorderSummaries()

        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_SUMMARY"])
        XCTAssertEqual(history.summary.knownRecorders, 1)
        XCTAssertEqual(history.activityHistory.source, .notProvided)
    }

    func testLoadVitalDBRecordersDoesNotReadRecorderIngressStatusFromRuntimeStatusWhenProviderIsInjected() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try writeLegacyRuntimeStatus(
            to: runtimeStatus,
            observation: VitalDBObservationDocument(
                observedAt: "2026-05-31T00:00:10Z",
                ready: true,
                recorderOnlineThresholdSeconds: 60
            )
        )
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeStatus: runtimeStatus.path,
                runtimeObservabilityDB: "/projection.sqlite"
            ),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(
                    VitalDBObservationDocument(
                        observedAt: "2026-05-31T00:00:10Z",
                        ready: true,
                        recorderOnlineThresholdSeconds: 60
                    ),
                    source: .guestControlAPI
                )
            },
            recorderIngressStatusReadProvider: StubRecorderIngressStatusReadProvider(result: nil)
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.summary.knownRecorders, 0)
    }

    func testRecorderIngressGuestStatusReadProviderReadsGuestControlAPI() {
        let provider = RuntimeRecorderIngressGuestStatusReadProvider(
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { baseURL in
                XCTAssertEqual(baseURL, "http://127.0.0.1:18330")
                return GuestVitalDBObservationGatewayStub(
                    read: .init(state: .unavailable),
                    recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult(
                        readState: .loaded,
                        httpStatus: "200",
                        document: RuntimeRecorderIngressStatusDocument(
                            recorders: [
                                RuntimeRecorderConnectionObservation(
                                    vrcode: "VR_GUEST",
                                    activeConnections: 1,
                                    selectedIp: "192.168.64.25",
                                    lastSeenAt: "2026-07-01T00:00:00+00:00"
                                )
                            ]
                        ),
                        readError: nil
                    )
                )
            }
        )

        let result = provider.loadRecorderIngressStatusRead()

        XCTAssertEqual(result?.readState, .loaded)
        XCTAssertEqual(result?.document?.recorders.map(\.vrcode), ["VR_GUEST"])
    }

    func testRecorderIngressGuestStatusReadProviderPreservesGuestReadFailure() {
        let provider = RuntimeRecorderIngressGuestStatusReadProvider(
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { _ in
                throw RuntimeGuestControlGatewayCapabilityError.unavailable("recorder-ingress-status")
            }
        )

        let result = provider.loadRecorderIngressStatusRead()

        XCTAssertEqual(result?.readState, .readFailed)
        XCTAssertEqual(result?.httpStatus, RuntimeHTTPStatusText.failed)
        XCTAssertTrue(result?.readError?.contains("guestControl=") == true)
    }

    func testLoadVitalDBRecorderActivityWindowUsesGuestActivityReadModel() {
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable()
            },
            guestVitalDBActivityProvider: RuntimeVitalDBGuestActivityProvider { vrcode in
                RuntimeGuestControlVitalDBRecorderActivityRead(
                    state: .loaded,
                    vrcode: vrcode,
                    buckets: [
                        VitalDBRecorderActivityBucketRecord(
                            vrcode: vrcode,
                            bucketStartedAt: "2026-07-01T00:00:00Z",
                            bucketSeconds: 60,
                            messageCount: 2,
                            byteCount: 128,
                            roomCount: 1,
                            firstObservedAt: "2026-07-01T00:00:00Z",
                            lastObservedAt: "2026-07-01T00:00:59Z"
                        ),
                    ],
                    readError: nil
                )
            }
        )

        let window = reader.loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "VR_GUEST",
            bucketSeconds: 60,
            period: .all,
            pageIndex: 0
        ))

        XCTAssertEqual(window.state, .loaded)
        XCTAssertEqual(window.buckets.map(\.messageCount), [2])
        XCTAssertNil(window.readError)
    }

    func testDiagnosticsProjectionReaderProjectsAssignmentsAndRelationshipEvents() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_DUP", online: true),
                VitalDBRecorderObservation(vrcode: "VR_FREE", online: true),
                VitalDBRecorderObservation(vrcode: "VR_STALE", online: false),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "A", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-b", name: "B", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-c", name: "C", vrcode: nil, online: true),
                VitalDBBedObservation(bedID: "bed-d", name: "D", vrcode: "VR_STALE", online: true),
            ]
        ))
        let reader = RuntimeVitalDBHostDiagnosticsProjectionReader(
            mode: .diagnostics,
            paths: RuntimePaths(runtimeObservabilityDB: database.path),
            makeVitalDBProjectionRepository: { _ in repository }
        )

        let history = RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
            reads: reader.relationshipProjectionReads()
        )

        XCTAssertEqual(history.state, .loaded)
        XCTAssertNil(history.readError)
        XCTAssertEqual(Set(history.assignments.map(\.bedID)), ["bed-a", "bed-b", "bed-d"])
        XCTAssertTrue(history.events.contains { $0.eventType == .duplicateAssignment && $0.severity == .warning })
        XCTAssertTrue(history.events.contains { $0.eventType == .unlinkedBed })
        XCTAssertTrue(history.events.contains { $0.eventType == .unlinkedRecorder })
        XCTAssertTrue(history.events.contains { $0.eventType == .staleLink })
    }

    func testDiagnosticsProjectionReaderReportsPartialStateWhenOnlyEventsProjectionFails() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "A", vrcode: "VR_A", online: true),
            ]
        ))
        try executeSQLite(database, sql: "DROP TABLE vitaldb_relationship_events")
        let reader = RuntimeVitalDBHostDiagnosticsProjectionReader(
            mode: .diagnostics,
            paths: RuntimePaths(runtimeObservabilityDB: database.path),
            makeVitalDBProjectionRepository: { _ in repository }
        )

        let history = RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
            reads: reader.relationshipProjectionReads()
        )

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.assignments.map(\.bedID), ["bed-a"])
        XCTAssertEqual(history.events, [])
        XCTAssertTrue(history.readError?.contains("events=") == true)
        XCTAssertFalse(history.readError?.contains("assignments=") == true)
    }

    func testVitalDBRelationshipsUsesGuestReadModelInsteadOfSQLiteProjection() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "A", vrcode: "VR_A", online: true),
            ]
        ))
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: database.path),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable()
            },
            guestVitalDBRelationshipProvider: .live(
                guestControlBaseURL: { "http://127.0.0.1:18330" },
                guestControlGateway: { _ in
                    GuestVitalDBObservationGatewayStub(
                        read: RuntimeGuestControlVitalDBObservationRead(state: .unavailable),
                        relationshipRead: RuntimeGuestControlVitalDBRelationshipRead(
                            state: .loaded,
                            assignments: [
                                RuntimeVitalBedAssignmentRecord(
                                    assignmentID: "guest-assignment-1",
                                    bedID: "bed-from-guest",
                                    bedName: "Guest Bed",
                                    vrcode: "VR_GUEST",
                                    startedAt: "2026-07-01T00:00:00+00:00",
                                    endedAt: nil,
                                    lastSeenAt: "2026-07-01T00:00:05+00:00",
                                    lastObservedAt: "2026-07-01T00:00:05+00:00",
                                    status: .online,
                                    patientConnected: true,
                                    observationCount: 2
                                ),
                            ],
                            events: []
                        )
                    )
                }
            )
        )

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.state, RuntimeVitalRelationshipHistoryState.loaded)
        XCTAssertEqual(history.assignments.map { $0.assignmentID }, ["guest-assignment-1"])
        XCTAssertEqual(history.assignments.map { $0.bedID }, ["bed-from-guest"])
        XCTAssertTrue(history.events.isEmpty)
        XCTAssertEqual(history.readError, nil)
    }

    func testLiveVitalDBRelationshipProviderPreservesGuestUnavailableRead() {
        let provider = RuntimeVitalDBGuestRelationshipProvider.live(
            guestControlBaseURL: { "http://127.0.0.1:18330" },
            guestControlGateway: { _ in
                GuestVitalDBObservationGatewayStub(
                    read: RuntimeGuestControlVitalDBObservationRead(state: .unavailable),
                    relationshipRead: RuntimeGuestControlVitalDBRelationshipRead(
                        state: .unavailable,
                        readError: "VitalDB relationship read model is empty."
                    )
                )
            }
        )

        let history = provider.load()

        XCTAssertEqual(history.state, .readFailed)
        XCTAssertEqual(history.assignments, [])
        XCTAssertEqual(history.events, [])
        XCTAssertEqual(history.readError, "VitalDB relationship read model is empty.")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-observability-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func executeSQLite(_ database: URL, sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK, let openedDB = db else {
            throw SQLiteTestFailure(
                message: sqlite3_errmsg(db).map { String(cString: $0) } ?? "sqlite open failed"
            )
        }
        defer {
            sqlite3_close(openedDB)
        }
        guard sqlite3_exec(openedDB, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteTestFailure(
                message: sqlite3_errmsg(openedDB).map { String(cString: $0) } ?? "sqlite exec failed"
            )
        }
    }

    private func runtimeEvent(id: String, timestamp: String) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: timestamp,
            product: "VitalServerHelper",
            status: .healthy,
            previousStatus: nil,
            operation: .health,
            message: "ready",
            runtimeVersion: "1.2.3",
            failureReasons: [],
            progress: nil
        )
    }

    private func writeRuntimeState(
        to url: URL,
        observation: VitalDBObservationDocument
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let observationData = try encoder.encode(observation)
        let observationJSON = String(decoding: observationData, as: UTF8.self)
        let json = """
        {
          "schemaVersion": 1,
          "vmIP": "192.168.64.2",
          "guestHTTP": "200",
          "redisUIHTTP": "200",
          "swaggerUIHTTP": "200",
          "vitalDBObservation": \(observationJSON)
        }
        """
        try Data(json.utf8).write(to: url)
    }

    private func writeLegacyRuntimeStatus(
        to url: URL,
        observation: VitalDBObservationDocument
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let observationData = try encoder.encode(observation)
        let observationJSON = String(decoding: observationData, as: UTF8.self)
        let json = """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-05-31T00:00:10Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/runtime",
          "runtimeVersion": "1.0.0",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "vmIP": "192.168.64.33",
          "proxyPort": 19090,
          "hostProxyHTTP": "200",
          "guestHTTP": "200",
          "redisUIHTTP": null,
          "swaggerUIHTTP": null,
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": [],
          "latestBackup": null,
          "vitalDBObservation": \(observationJSON)
        }
        """
        try Data(json.utf8).write(to: url)
    }
}

private struct SQLiteTestFailure: Error {
    let message: String
}

private struct ProjectionReadFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

private struct FailingVitalDBProjectionRepository: RuntimeVitalDBObservationProjectionReading {
    var latestObservation: VitalDBObservationDocument?
    var observations: [VitalDBObservationDocument] = []
    var activityBuckets: [VitalDBRecorderActivityBucketRecord] = []
    var assignments: [VitalDBBedAssignmentRecord] = []
    var relationshipEvents: [VitalDBRelationshipEventRecord] = []
    var latestObservationError: Error?
    var observationError: Error?
    var activityError: Error?
    var assignmentError: Error?
    var relationshipEventError: Error?

    func loadLatestObservation() throws -> VitalDBObservationDocument? {
        if let latestObservationError {
            throw latestObservationError
        }
        return latestObservation
    }

    func loadObservations(limit: Int) throws -> [VitalDBObservationDocument] {
        if let observationError {
            throw observationError
        }
        return Array(observations.prefix(limit))
    }

    func loadRecorderActivityBuckets(
        query: VitalDBRecorderActivityBucketQuery
    ) throws -> [VitalDBRecorderActivityBucketRecord] {
        if let activityError {
            throw activityError
        }
        return Array(activityBuckets.prefix(query.limit))
    }

    func loadBedAssignments(limit: Int) throws -> [VitalDBBedAssignmentRecord] {
        if let assignmentError {
            throw assignmentError
        }
        return Array(assignments.prefix(limit))
    }

    func loadRelationshipEvents(limit: Int) throws -> [VitalDBRelationshipEventRecord] {
        if let relationshipEventError {
            throw relationshipEventError
        }
        return Array(relationshipEvents.prefix(limit))
    }
}

private struct StubRecorderIngressStatusReadProvider: RuntimeRecorderIngressStatusReadProviding {
    let result: RuntimeRecorderIngressStatusReadResult?

    func loadRecorderIngressStatusRead() -> RuntimeRecorderIngressStatusReadResult? {
        result
    }
}

private struct GuestVitalDBObservationGatewayStub: RuntimeGuestControlGateway {
    let read: RuntimeGuestControlVitalDBObservationRead
    let recorderRead: RuntimeGuestControlVitalDBRecorderRead
    let bedRead: RuntimeGuestControlVitalDBBedRead
    let relationshipRead: RuntimeGuestControlVitalDBRelationshipRead
    let activityRead: RuntimeGuestControlVitalDBRecorderActivityRead
    let recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult

    init(
        read: RuntimeGuestControlVitalDBObservationRead,
        recorderRead: RuntimeGuestControlVitalDBRecorderRead = .init(state: .unavailable),
        bedRead: RuntimeGuestControlVitalDBBedRead = .init(state: .unavailable),
        relationshipRead: RuntimeGuestControlVitalDBRelationshipRead = .init(state: .unavailable),
        activityRead: RuntimeGuestControlVitalDBRecorderActivityRead = .init(state: .unavailable),
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult = .init(
            readState: .readFailed,
            httpStatus: RuntimeHTTPStatusText.failed,
            document: nil,
            readError: "recorder ingress status read was not provided"
        )
    ) {
        self.read = read
        self.recorderRead = recorderRead
        self.bedRead = bedRead
        self.relationshipRead = relationshipRead
        self.activityRead = activityRead
        self.recorderIngressStatusRead = recorderIngressStatusRead
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("listServices")
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("stackStatus")
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("serviceStatus \(service)")
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("startService \(service)")
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("stopService \(service)")
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("restartService \(service)")
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("reconcileServices")
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        throw GuestVitalDBObservationGatewayStubError.unexpectedCall("operation \(operationId)")
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        read
    }

    func vitalDBRecorders() throws -> RuntimeGuestControlVitalDBRecorderRead {
        recorderRead
    }

    func vitalDBRecorderActivity(_ vrcode: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead {
        guard activityRead.vrcode == nil || activityRead.vrcode == vrcode else {
            throw GuestVitalDBObservationGatewayStubError.unexpectedCall(
                "vitalDBRecorderActivity \(vrcode)"
            )
        }
        return activityRead
    }

    func vitalDBBeds() throws -> RuntimeGuestControlVitalDBBedRead {
        bedRead
    }

    func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead {
        relationshipRead
    }

    func recorderIngressStatus() throws -> RuntimeRecorderIngressStatusReadResult {
        recorderIngressStatusRead
    }
}

private enum GuestVitalDBObservationGatewayStubError: Error, CustomStringConvertible {
    case unexpectedCall(String)

    var description: String {
        switch self {
        case .unexpectedCall(let method):
            "unexpected guest control gateway call: \(method)"
        }
    }
}

private final class RecordingRuntimeCommandRunner: RuntimeCommandRunner {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var result = RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    private(set) var calls: [Call] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return result
    }
}

private struct DefaultSnapshotObservabilityReader: RuntimeObservabilityReading {
    let snapshot: RuntimeVitalDBObservationSnapshot

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [])
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [])
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        snapshot
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory()
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory()
    }
}

private func makeVitalDBProjectionRepository(url: URL) -> SQLiteVitalDBObservationRepository {
    let relationshipProjection = PlanVitalDBRelationshipProjectionUseCase()
    let store = SQLiteRuntimeObservabilityStore(
        url: url,
        relationshipProjectionPlanner: relationshipProjection.projectionPlan
    )
    return SQLiteVitalDBObservationRepository(store: store)
}

private final class ObservabilityPathStateFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let pathStates: [String: RuntimePathState]

    init(pathStates: [String: RuntimePathState]) {
        self.pathStates = pathStates
    }

    func fileExists(_ url: URL) -> Bool { pathStates[url.path] == .file }
    func directoryExists(_ url: URL) -> Bool { pathStates[url.path] == .directory }
    func isExecutableFile(atPath path: String) -> Bool { false }

    func fileState(atPath path: String) -> RuntimeFileState {
        fileState(at: URL(fileURLWithPath: path))
    }

    func fileState(at url: URL) -> RuntimeFileState {
        switch pathState(at: url) {
        case .file, .directory, .other:
            .present
        case .missing:
            .missing
        case .inspectFailed(let reason):
            .inspectFailed(reason)
        case .unknown(let value):
            .unknown(value)
        }
    }

    func pathState(at url: URL) -> RuntimePathState {
        pathStates[url.path] ?? .missing
    }

    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoSuchFile) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoSuchFile) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoSuchFile) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        throw CocoaError(.fileReadNoSuchFile)
    }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        throw CocoaError(.fileReadNoSuchFile)
    }
}
