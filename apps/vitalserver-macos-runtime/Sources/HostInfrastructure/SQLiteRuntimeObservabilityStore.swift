import Foundation
import SQLite3
import Contracts
import Core

public enum SQLiteRuntimeObservabilityStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case decodeFailed(String)
}

public struct SQLiteRuntimeObservabilityStore {
    public static let schemaVersion = 2

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func initialize() throws {
        try withDatabase { db in
            try execute(db, sql: "PRAGMA journal_mode=WAL")
            try execute(db, sql: "PRAGMA foreign_keys=ON")
            try execute(db, sql: """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version integer primary key,
              applied_at text not null
            )
            """)
            try execute(db, sql: """
            CREATE TABLE IF NOT EXISTS runtime_events (
              id text primary key,
              timestamp text not null,
              source text not null,
              event_type text not null,
              status text,
              previous_status text,
              operation text,
              message text,
              runtime_version text,
              payload_json text not null
            )
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_runtime_events_timestamp_id
              ON runtime_events(timestamp, id)
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_runtime_events_event_type_timestamp
              ON runtime_events(event_type, timestamp)
            """)
            try execute(db, sql: """
            CREATE TABLE IF NOT EXISTS vitaldb_observation_snapshots (
              observed_at text primary key,
              ready integer not null,
              recorder_count integer not null,
              anomaly_count integer not null,
              payload_json text not null
            )
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_observation_snapshots_observed_at
              ON vitaldb_observation_snapshots(observed_at)
            """)
            try execute(
                db,
                sql: "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                bindings: [.int(Self.schemaVersion), .text(Self.now())]
            )
        }
    }

    public func append(_ event: RuntimeEventDocument) throws {
        try initialize()
        try withDatabase { db in
            try insert(event, db: db)
        }
    }

    public func rebuild(from events: [RuntimeEventDocument]) throws {
        try removeDatabaseFiles()
        try initialize()
        try withDatabase { db in
            try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                for event in events {
                    try insert(event, db: db)
                }
                try execute(db, sql: "COMMIT")
            } catch {
                try? execute(db, sql: "ROLLBACK")
                throw error
            }
        }
    }

    public func recent(limit: Int) -> [RuntimeEventDocument] {
        guard limit > 0 else {
            return []
        }
        do {
            try initialize()
            return try withDatabase { db in
                return Array(try queryEvents(
                    db,
                    sql: """
                    SELECT payload_json
                    FROM runtime_events
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ?
                    """,
                    bindings: [.int(limit)]
                ).reversed())
            }
        } catch {
            return []
        }
    }

    public func recent(limit: Int, eventType: RuntimeEventType?, since: String?) -> [RuntimeEventDocument] {
        query(RuntimeEventQuery(limit: limit, eventType: eventType, since: since)).events
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        guard query.limit > 0 else {
            return RuntimeEventPage(events: [])
        }
        do {
            try initialize()
            return try withDatabase { db in
                var predicates: [String] = []
                var bindings: [SQLiteBinding] = []

                if let eventType = query.eventType {
                    predicates.append("event_type = ?")
                    bindings.append(.text(eventType.rawValue))
                }
                if let since = query.since {
                    predicates.append("timestamp >= ?")
                    bindings.append(.text(since))
                }
                if let before = query.before {
                    predicates.append("(timestamp < ? OR (timestamp = ? AND id < ?))")
                    bindings.append(.text(before.timestamp))
                    bindings.append(.text(before.timestamp))
                    bindings.append(.text(before.id))
                }

                let whereClause = predicates.isEmpty ? "" : "WHERE \(predicates.joined(separator: " AND "))"
                bindings.append(.int(query.limit + 1))

                let events = try queryEvents(
                    db,
                    sql: """
                    SELECT payload_json
                    FROM runtime_events
                    \(whereClause)
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ?
                    """,
                    bindings: bindings
                )
                let hasMore = events.count > query.limit
                let pageEvents = Array(events.prefix(query.limit).reversed())
                return RuntimeEventPage(events: pageEvents, nextCursor: nextCursor(for: pageEvents, hasMore: hasMore))
            }
        } catch {
            return RuntimeEventPage(events: [])
        }
    }

    public func append(_ observation: VitalDBObservationDocument) throws {
        try initialize()
        try withDatabase { db in
            try insert(observation, db: db)
        }
    }

    public func latestVitalDBObservation() -> VitalDBObservationDocument? {
        do {
            try initialize()
            return try withDatabase { db in
                let observations = try queryVitalDBObservations(
                    db,
                    sql: """
                    SELECT payload_json
                    FROM vitaldb_observation_snapshots
                    ORDER BY observed_at DESC
                    LIMIT 1
                    """,
                    bindings: []
                )
                return observations.first
            }
        } catch {
            return nil
        }
    }

    public func vitalDBObservations(limit: Int = 1000) -> [VitalDBObservationDocument] {
        guard limit > 0 else {
            return []
        }
        do {
            try initialize()
            return try withDatabase { db in
                let observations = try queryVitalDBObservations(
                    db,
                    sql: """
                    SELECT payload_json
                    FROM vitaldb_observation_snapshots
                    ORDER BY observed_at DESC
                    LIMIT ?
                    """,
                    bindings: [.int(limit)]
                )
                return Array(observations.reversed())
            }
        } catch {
            return []
        }
    }

    private func nextCursor(for events: [RuntimeEventDocument], hasMore: Bool) -> RuntimeEventCursor? {
        guard hasMore, let first = events.first else {
            return nil
        }
        return RuntimeEventCursor(timestamp: first.timestamp, id: first.id)
    }

    private func queryEvents(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [RuntimeEventDocument] {
        let decoder = JSONDecoder()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)

        var events: [RuntimeEventDocument] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return events
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
            }
            guard let rawPayload = sqlite3_column_text(statement, 0) else {
                continue
            }
            let payload = String(cString: rawPayload)
            guard let data = payload.data(using: .utf8),
                  let event = try? decoder.decode(RuntimeEventDocument.self, from: data) else {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(payload)
            }
            events.append(event)
        }
    }

    private func insert(_ event: RuntimeEventDocument, db: OpaquePointer) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = String(decoding: try encoder.encode(event), as: UTF8.self)

        try execute(
            db,
            sql: """
            INSERT OR REPLACE INTO runtime_events(
              id,
              timestamp,
              source,
              event_type,
              status,
              previous_status,
              operation,
              message,
              runtime_version,
              payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.id),
                .text(event.timestamp),
                .text(event.source),
                .text(event.eventType.rawValue),
                .text(event.status.rawValue),
                .optionalText(event.previousStatus?.rawValue),
                .text(event.operation.rawValue),
                .text(event.message),
                .text(event.runtimeVersion),
                .text(payload),
            ]
        )
    }

    private func insert(_ observation: VitalDBObservationDocument, db: OpaquePointer) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = String(decoding: try encoder.encode(observation), as: UTF8.self)

        try execute(
            db,
            sql: """
            INSERT OR REPLACE INTO vitaldb_observation_snapshots(
              observed_at,
              ready,
              recorder_count,
              anomaly_count,
              payload_json
            ) VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(observation.observedAt),
                .int(observation.ready ? 1 : 0),
                .int(observation.recorders.count),
                .int(observation.anomalies.count),
                .text(payload),
            ]
        )
    }

    private func queryVitalDBObservations(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBObservationDocument] {
        let decoder = JSONDecoder()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)

        var observations: [VitalDBObservationDocument] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return observations
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
            }
            guard let rawPayload = sqlite3_column_text(statement, 0) else {
                continue
            }
            let payload = String(cString: rawPayload)
            guard let data = payload.data(using: .utf8),
                  let observation = try? decoder.decode(VitalDBObservationDocument.self, from: data) else {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(payload)
            }
            observations.append(observation)
        }
    }

    private func removeDatabaseFiles() throws {
        let fileManager = FileManager.default
        for path in [url.path, "\(url.path)-wal", "\(url.path)-shm"] {
            guard fileManager.fileExists(atPath: path) else {
                continue
            }
            try fileManager.removeItem(atPath: path)
        }
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let openedDB = db else {
            let message = db.map(errorMessage) ?? "unknown sqlite open error"
            sqlite3_close(db)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedDB)
        }
        return try operation(openedDB)
    }

    private func execute(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding] = []
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
            }
        }
    }

    private func bind(
        _ bindings: [SQLiteBinding],
        to statement: OpaquePointer?,
        db: OpaquePointer
    ) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .optionalText(let value):
                if let value {
                    result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            }
            guard result == SQLITE_OK else {
                throw SQLiteRuntimeObservabilityStoreError.bindFailed(errorMessage(db))
            }
        }
    }

    private func errorMessage(_ db: OpaquePointer) -> String {
        sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown sqlite error"
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private enum SQLiteBinding {
    case int(Int)
    case text(String)
    case optionalText(String?)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
