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
        let reader = SystemRuntimeObservabilityReader(paths: RuntimePaths(runtimeObservabilityDB: database.path))

        let observation = reader.loadVitalDBObservation()

        XCTAssertEqual(observation?.observedAt, "2026-05-31T00:00:00Z")
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
            statusObservationProvider: { statusObservation }
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.updatedAt, "2026-05-31T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STATUS"])
        XCTAssertEqual(history.activityHistory.source, .unavailable)
        XCTAssertTrue(history.activityHistory.readError?.contains("observations=") == true)
        XCTAssertTrue(history.activityHistory.readError?.contains("activityBuckets=") == true)
    }

    func testLoadVitalDBRecordersReturnsNilStatusFallbackWhenStatusFileIsMissing() throws {
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }
        let database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                runtimeObservabilityDB: database.path
            )
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertNil(history.updatedAt)
        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.activityHistory.source, .sqliteProjection)
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
