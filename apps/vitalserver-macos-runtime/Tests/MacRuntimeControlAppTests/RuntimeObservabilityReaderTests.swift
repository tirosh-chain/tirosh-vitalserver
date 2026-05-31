import Contracts
import HostInfrastructure
@testable import MacHostRuntimeAdapter
import RuntimeControl
import XCTest

final class RuntimeObservabilityReaderTests: XCTestCase {
    func testProtocolDefaultObservationSnapshotWrapsOptionalObservation() {
        let reader = DefaultSnapshotObservabilityReader(observation: VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        ))

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
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeEvents: runtimeEvents.path,
                runtimeObservabilityDB: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB).path
            )
        )

        let history = reader.loadRuntimeEvents(limit: 5)

        XCTAssertEqual(history.events.map(\.id), ["event-limit"])
        XCTAssertEqual(history.matchingCount, 1)
    }

    func testLoadVitalDBObservationReturnsLatestSQLiteObservation() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = SQLiteVitalDBObservationRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        ))
        let reader = SystemRuntimeObservabilityReader(paths: RuntimePaths(
            runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
            runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
            runtimeObservabilityDB: database.path
        ))

        let observation = reader.loadVitalDBObservation()

        XCTAssertEqual(observation?.observedAt, "2026-05-31T00:00:00Z")
    }

    func testLoadVitalDBObservationPrefersFreshGuestRuntimeStateOverSQLiteProjection() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let repository = SQLiteVitalDBObservationRepository(url: database)
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
        let reader = SystemRuntimeObservabilityReader(paths: RuntimePaths(
            runtimeState: runtimeState.path,
            runtimeObservabilityDB: database.path
        ))

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:05Z")
        XCTAssertEqual(snapshot.observation?.recorders.first?.stale, true)
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
            paths: RuntimePaths(runtimeObservabilityDB: "/dev/null/vital-observability.sqlite"),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                .loaded(statusObservation, source: .runtimeStatus)
            }
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.updatedAt, "2026-05-31T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STATUS"])
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertTrue(history.activityHistory.readError?.contains("observations=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("activityBuckets=") == true)
    }

    func testLoadVitalDBRecordersUsesFreshGuestRuntimeStateForCurrentStatus() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let repository = SQLiteVitalDBObservationRepository(url: database)
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
        let reader = SystemRuntimeObservabilityReader(paths: RuntimePaths(
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
        let repository = SQLiteVitalDBObservationRepository(url: database)
        try repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_PROJECTED", online: true),
            ]
        ))
        try Data("not-json".utf8).write(to: runtimeState)
        let reader = SystemRuntimeObservabilityReader(paths: RuntimePaths(
            runtimeState: runtimeState.path,
            runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
            runtimeObservabilityDB: database.path
        ))

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.updatedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_PROJECTED"])
        XCTAssertEqual(history.activityHistory.source, .sqliteProjection)
        XCTAssertTrue(history.activityHistory.readError?.contains("currentObservation=runtimeState=") == true)
    }

    func testLoadVitalDBRecordersReturnsNilStatusFallbackWhenStatusFileIsMissing() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                runtimeObservabilityDB: database.path
            )
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertNil(history.updatedAt)
        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertNotNil(history.activityHistory.readError)
    }

    func testLoadVitalDBRelationshipsProjectsAssignmentsAndRelationshipEvents() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let repository = SQLiteVitalDBObservationRepository(url: database)
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
        let reader = SystemRuntimeObservabilityReader(paths: RuntimePaths(runtimeObservabilityDB: database.path))

        let history = reader.loadVitalDBRelationships()

        XCTAssertNil(history.readError)
        XCTAssertEqual(Set(history.assignments.map(\.bedID)), ["bed-a", "bed-b", "bed-d"])
        XCTAssertTrue(history.events.contains { $0.eventType == .duplicateAssignment && $0.severity == .warning })
        XCTAssertTrue(history.events.contains { $0.eventType == .unlinkedBed })
        XCTAssertTrue(history.events.contains { $0.eventType == .unlinkedRecorder })
        XCTAssertTrue(history.events.contains { $0.eventType == .staleLink })
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

    private func runtimeEvent(id: String, timestamp: String) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: timestamp,
            product: "TiroshVitalServer",
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
}

private struct DefaultSnapshotObservabilityReader: RuntimeObservabilityReading {
    let observation: VitalDBObservationDocument?

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [])
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [])
    }

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        observation
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory()
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory()
    }
}
