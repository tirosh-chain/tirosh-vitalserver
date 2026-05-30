import Contracts
import Core
import Foundation
import HostInfrastructure
import XCTest

final class SQLiteRuntimeObservabilityStoreTests: XCTestCase {
    func testAppendsAndReadsRuntimeEventsByRecency() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try harness.store.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .auditProxyObserved))
        try harness.store.append(event(id: "event-3", timestamp: "2026-05-24T00:02:00Z", type: .containerObserved))

        XCTAssertEqual(harness.store.recent(limit: 2).map(\.id), ["event-2", "event-3"])
    }

    func testQueriesRuntimeEventsByTypeAndTimestamp() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try harness.store.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .auditProxyObserved))
        try harness.store.append(event(id: "event-3", timestamp: "2026-05-24T00:02:00Z", type: .auditProxyObserved))

        let events = harness.store.recent(
            limit: 10,
            eventType: .auditProxyObserved,
            since: "2026-05-24T00:02:00Z"
        )

        XCTAssertEqual(events.map(\.id), ["event-3"])
    }

    func testQueriesRuntimeEventsWithCursor() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try harness.store.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .auditProxyObserved))
        try harness.store.append(event(id: "event-3", timestamp: "2026-05-24T00:02:00Z", type: .containerObserved))

        let firstPage = harness.store.query(RuntimeEventQuery(limit: 2))
        let secondPage = harness.store.query(RuntimeEventQuery(limit: 2, before: firstPage.nextCursor))

        XCTAssertEqual(firstPage.events.map(\.id), ["event-2", "event-3"])
        XCTAssertEqual(firstPage.nextCursor, RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2"))
        XCTAssertEqual(secondPage.events.map(\.id), ["event-1"])
        XCTAssertNil(secondPage.nextCursor)
    }

    func testCompositeRepositoryCatchesUpSQLiteFromJSONLWhenSQLiteIsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            catchUpIntervalSeconds: 0
        )

        try jsonl.append(event(id: "jsonl-event", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["jsonl-event"])
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["jsonl-event"])
    }

    func testCompositeRepositoryReadsSQLiteWhenAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

        try repository.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1"])
    }

    func testCompositeRepositoryPeriodicallyCatchesUpStaleSQLiteIndexFromJSONL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let baseDate = Date(timeIntervalSince1970: 1_779_552_000)

        let first = event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged)
        let second = event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .containerObserved)
        try jsonl.append(first)
        try jsonl.append(second)
        try sqlite.append(first)
        try sqlite.markCaughtUp(at: baseDate)

        let notDueRepository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            catchUpIntervalSeconds: 30,
            now: { baseDate.addingTimeInterval(10) }
        )
        XCTAssertEqual(notDueRepository.recent(limit: 10).map(\.id), ["event-1"])

        let dueRepository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            catchUpIntervalSeconds: 30,
            now: { baseDate.addingTimeInterval(31) }
        )
        XCTAssertEqual(dueRepository.recent(limit: 10).map(\.id), ["event-1", "event-2"])
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1", "event-2"])
    }

    func testCompositeRepositoryRebuildsSQLiteIndexFromJSONLWhenDatabaseIsCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqliteURL = directory.appendingPathComponent("events.sqlite")
        let sqlite = SQLiteRuntimeEventRepository(url: sqliteURL)
        let repository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            catchUpIntervalSeconds: 0
        )

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try Data("not a sqlite database".utf8).write(to: sqliteURL)

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1"])
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1"])
    }

    func testCompositeRepositoryCatchUpSkipsBrokenJSONLLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonlURL = directory.appendingPathComponent("events.jsonl")
        let jsonl = JSONLRuntimeEventRepository(url: jsonlURL)
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            catchUpIntervalSeconds: 0
        )

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        let handle = try FileHandle(forWritingTo: jsonlURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        handle.write(Data("{broken json}\n".utf8))
        try jsonl.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .containerObserved))

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1", "event-2"])
    }

    func testStoresAndLoadsLatestVitalDBObservation() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }
        let older = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )
        let newer = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ]
        )

        try harness.store.append(older)
        try harness.store.append(newer)

        XCTAssertEqual(harness.store.latestVitalDBObservation(), newer)
    }

    func testLoadsVitalDBObservationsInChronologicalOrder() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }
        let older = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )
        let newer = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )

        try harness.store.append(newer)
        try harness.store.append(older)

        XCTAssertEqual(harness.store.vitalDBObservations().map(\.observedAt), [
            "2026-05-25T00:00:00Z",
            "2026-05-25T00:01:00Z",
        ])
    }

    func testProjectsVitalDBBedAssignmentsAcrossObservations() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        ))
        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:01:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        ))

        let assignments = harness.store.vitalDBBedAssignments()

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments[0].bedID, "bed-a")
        XCTAssertEqual(assignments[0].vrcode, "VR_A")
        XCTAssertEqual(assignments[0].startedAt, "2026-05-25T00:00:00Z")
        XCTAssertNil(assignments[0].endedAt)
        XCTAssertEqual(assignments[0].lastObservedAt, "2026-05-25T00:01:00Z")
        XCTAssertEqual(assignments[0].observationCount, 2)
    }

    func testRelationshipProjectionIsIdempotentForSameObservationTimestamp() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        )

        try harness.store.append(observation)
        try harness.store.append(observation)

        let assignments = harness.store.vitalDBBedAssignments()

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments[0].observationCount, 1)
    }


    func testProjectsVitalDBRelationshipHandoff() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_A", online: true),
            ]
        ))
        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:05:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_B", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_B", online: true),
            ]
        ))

        let assignments = harness.store.vitalDBBedAssignments()
        let events = harness.store.vitalDBRelationshipEvents()

        XCTAssertEqual(assignments.map(\.vrcode), ["VR_B", "VR_A"])
        XCTAssertNil(assignments[0].endedAt)
        XCTAssertEqual(assignments[1].endedAt, "2026-05-25T00:05:00Z")
        XCTAssertTrue(events.contains {
            $0.eventType == .handoff
                && $0.bedID == "bed-a"
                && $0.vrcode == "VR_B"
                && $0.previousVrcode == "VR_A"
        })
    }

    func testProjectsVitalDBRelationshipAnomalies() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_DUP", online: true),
                VitalDBRecorderObservation(vrcode: "VR_FREE", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-b", name: "OR B", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-c", name: "OR C", vrcode: nil, online: true),
            ]
        ))

        let eventTypes = Set(harness.store.vitalDBRelationshipEvents().map(\.eventType))

        XCTAssertTrue(eventTypes.contains(.duplicateAssignment))
        XCTAssertTrue(eventTypes.contains(.unlinkedBed))
        XCTAssertTrue(eventTypes.contains(.unlinkedRecorder))
    }

    private func event(id: String, timestamp: String, type: RuntimeEventType) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: type,
            timestamp: timestamp,
            product: "TiroshVitalServer",
            status: .healthy,
            previousStatus: nil,
            operation: .health,
            message: "message",
            runtimeVersion: "0.1.0",
            failureReasons: [],
            containerObservation: nil,
            progress: nil
        )
    }
}

private struct SQLiteStoreHarness {
    let directory: URL
    let store: SQLiteRuntimeObservabilityStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = SQLiteRuntimeObservabilityStore(url: directory.appendingPathComponent("runtime-observability.sqlite"))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
