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

    func testLoadVitalDBObservationSnapshotReturnsLatestSQLiteObservation() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = makeVitalDBProjectionRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        ))
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(
            runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
            runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:00Z")
    }

    func testLoadVitalDBObservationSnapshotPrefersFreshGuestRuntimeStateOverSQLiteProjection() throws {
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

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:05Z")
        XCTAssertEqual(snapshot.observation?.recorders.first?.stale, true)
    }

    func testLoadVitalDBObservationReportsMissingRuntimeStateWhenUsingStatusObservation() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try writeRuntimeStatus(
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

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:10Z")
        XCTAssertTrue(snapshot.readError?.contains("runtimeState=missing") == true)
        XCTAssertFalse(snapshot.readError?.contains("runtimeStatus=missing") == true)
    }

    func testLoadVitalDBObservationReportsUnexpectedRuntimeStatePathWhenUsingStatusObservation() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try FileManager.default.createDirectory(at: runtimeState, withIntermediateDirectories: true)
        try writeRuntimeStatus(
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
            runtimeState: runtimeState.path,
            runtimeStatus: runtimeStatus.path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:10Z")
        XCTAssertTrue(snapshot.readError?.contains("runtimeState=runtime state path state is unexpected") == true)
        XCTAssertTrue(snapshot.readError?.contains("state=directory") == true)
    }

    func testLoadVitalDBObservationPreservesRuntimeStatusPathInspectionFailureFromInjectedFileStore() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
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
        XCTAssertTrue(snapshot.readError?.contains("runtimeState=missing") == true)
        XCTAssertTrue(snapshot.readError?.contains(
            "runtimeStatus=runtime status document path inspection failed path=\(runtimeStatus.path) reason=permission denied"
        ) == true)
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
        XCTAssertTrue(snapshot.readError?.contains("runtimeState=missing") == true)
        XCTAssertTrue(snapshot.readError?.contains("runtimeStatus=missing") == true)
    }

    func testLoadVitalDBRecordersPreservesProjectionReadFailuresWithStatusProviderFallback() {
        let statusObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_STATUS", online: true),
            ]
        )
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(statusObservation, source: .runtimeStatus)
            },
            makeVitalDBProjectionRepository: { _ in
                FailingVitalDBProjectionRepository(
                    observationError: ProjectionReadFailure(message: "observations unavailable"),
                    activityError: ProjectionReadFailure(message: "activity unavailable")
                )
            }
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.updatedAt, "2026-05-31T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STATUS"])
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertTrue(history.readError?.contains("observations=") == true)
        XCTAssertTrue(history.readError?.contains("activityBuckets=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("observations=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("activityBuckets=") == true)
    }

    func testLoadVitalDBRelationshipsPreservesInjectedPartialProjectionReadFailure() {
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(runtimeObservabilityDB: "/projection.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .unavailable()
            },
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

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.assignments.map(\.bedID), ["bed-a"])
        XCTAssertEqual(history.events, [])
        XCTAssertTrue(history.readError?.contains("events=") == true)
        XCTAssertTrue(history.readError?.contains("events unavailable") == true)
        XCTAssertFalse(history.readError?.contains("assignments=") == true)
    }

    func testLoadVitalDBRecordersUsesFreshGuestRuntimeStateForCurrentStatus() throws {
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

        XCTAssertEqual(history.updatedAt, "2026-05-31T00:00:05Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_LIVE"])
        XCTAssertEqual(history.recorders.first?.status, .stale)
        XCTAssertEqual(history.recorders.first?.lastSeenAt, "2026-05-31T00:00:05Z")
        XCTAssertEqual(history.recorders.first?.observationCount, 2)
    }

    func testLoadVitalDBRecordersReportsCurrentObservationReadIssue() throws {
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

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.updatedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_PROJECTED"])
        XCTAssertEqual(history.activityHistory.source, .sqliteProjection)
        XCTAssertTrue(history.readError?.contains("currentObservation=runtimeState=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("currentObservation=runtimeState=") == true)
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
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertTrue(history.readError?.contains("runtimeState=missing") == true)
        XCTAssertTrue(history.readError?.contains("runtimeStatus=missing") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("runtimeState=missing") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("runtimeStatus=missing") == true)
    }

    func testLoadVitalDBRelationshipsProjectsAssignmentsAndRelationshipEvents() throws {
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
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(runtimeObservabilityDB: database.path))

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.state, .loaded)
        XCTAssertNil(history.readError)
        XCTAssertEqual(Set(history.assignments.map(\.bedID)), ["bed-a", "bed-b", "bed-d"])
        XCTAssertTrue(history.events.contains { $0.eventType == .duplicateAssignment && $0.severity == .warning })
        XCTAssertTrue(history.events.contains { $0.eventType == .unlinkedBed })
        XCTAssertTrue(history.events.contains { $0.eventType == .unlinkedRecorder })
        XCTAssertTrue(history.events.contains { $0.eventType == .staleLink })
    }

    func testLoadVitalDBRelationshipsReportsPartialStateWhenOnlyEventsProjectionFails() throws {
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
        let reader = SystemRuntimeObservabilityReader.live(paths: RuntimePaths(runtimeObservabilityDB: database.path))

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.assignments.map(\.bedID), ["bed-a"])
        XCTAssertEqual(history.events, [])
        XCTAssertTrue(history.readError?.contains("events=") == true)
        XCTAssertFalse(history.readError?.contains("assignments=") == true)
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
            containerObservation: nil,
            progress: nil
        )
    }

    private func writeRuntimeState(
        to url: URL,
        observation: VitalDBObservationDocument
    ) throws {
        let document = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            vitalDBObservation: observation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: url)
    }

    private func writeRuntimeStatus(
        to url: URL,
        observation: VitalDBObservationDocument
    ) throws {
        let document = RuntimeStatusDocument(
            schemaVersion: 2,
            product: "VitalServerHelper",
            status: .healthy,
            operation: .health,
            message: "ok",
            updatedAt: "2026-05-31T00:00:10Z",
            productRoot: "/tmp/product",
            runtimeHome: "/tmp/runtime",
            runtimeVersion: "1.0.0",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: "192.168.64.33",
            proxyPort: 19090,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: [],
            latestBackup: nil,
            vitalDBObservation: observation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: url)
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
