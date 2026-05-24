import Contracts
import Core
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

    func testCompositeRepositoryFallsBackToJSONLWhenSQLiteIsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

        try jsonl.append(event(id: "jsonl-event", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["jsonl-event"])
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

    func testCompositeRepositoryRebuildsSQLiteFromJSONLWhenDatabaseIsCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqliteURL = directory.appendingPathComponent("events.sqlite")
        let sqlite = SQLiteRuntimeEventRepository(url: sqliteURL)
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try Data("not a sqlite database".utf8).write(to: sqliteURL)

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1"])
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1"])
    }

    func testCompositeRepositoryRebuildSkipsBrokenJSONLLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonlURL = directory.appendingPathComponent("events.jsonl")
        let jsonl = JSONLRuntimeEventRepository(url: jsonlURL)
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

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
