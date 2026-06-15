import Contracts
import Foundation
import SQLite3
import Errors

extension SQLiteRuntimeObservabilityStore {
    public func append(_ event: RuntimeEventDocument) throws {
        try initialize()
        try database.withDatabase { db in
            try insert(event, db: db)
        }
    }

    public func upsertRuntimeEvents(_ events: [RuntimeEventDocument]) throws {
        try initialize()
        try database.withDatabase { db in
            try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                for event in events {
                    try insert(event, db: db)
                }
                try execute(db, sql: "COMMIT")
            } catch {
                try rollbackTransactionAfterFailure(db, originalError: error)
            }
        }
    }

    public func rebuild(from events: [RuntimeEventDocument]) throws {
        try database.removeDatabaseFiles()
        try initialize()
        try database.withDatabase { db in
            try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                for event in events {
                    try insert(event, db: db)
                }
                try execute(db, sql: "COMMIT")
            } catch {
                try rollbackTransactionAfterFailure(db, originalError: error)
            }
        }
    }

    public func runtimeEventIndexCatchUpDue(
        now: Date,
        intervalSeconds: TimeInterval
    ) -> RuntimeEventIndexCatchUpDueRead {
        do {
            try initialize()
            let lastCaughtUpAt = try runtimeEventIndexStateValue(for: "last_caught_up_at")
            guard let lastCaughtUpAt,
                  let lastCaughtUpAtSeconds = TimeInterval(lastCaughtUpAt) else {
                return .due
            }
            return now.timeIntervalSince1970 - lastCaughtUpAtSeconds >= intervalSeconds ? .due : .notDue
        } catch {
            return .dueAfterReadFailure(String(describing: error))
        }
    }

    public func markRuntimeEventIndexCaughtUp(at date: Date) throws {
        try initialize()
        try database.withDatabase { db in
            try execute(
                db,
                sql: """
                INSERT OR REPLACE INTO runtime_event_index_state(key, value)
                VALUES ('last_caught_up_at', ?)
                """,
                bindings: [.text(String(date.timeIntervalSince1970))]
            )
        }
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        guard query.limit > 0 else {
            return RuntimeEventPage(events: [])
        }
        do {
            return try database.withReadOnlyDatabase { db in
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
                let count = try countRows(
                    db,
                    sql: """
                    SELECT COUNT(*)
                    FROM runtime_events
                    \(whereClause)
                    """,
                    bindings: bindings
                )

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
                return RuntimeEventPage(
                    events: pageEvents,
                    nextCursor: nextCursor(for: pageEvents, hasMore: hasMore),
                    matchingCount: count
                )
            }
        } catch {
            return .failed(readError: String(describing: error))
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
        return try queryRows(db, sql: sql, bindings: bindings) { statement in
            guard let payload = columnText(statement, 0) else {
                throw SQLiteRuntimeObservabilityStoreError.missingColumn(
                    table: "runtime_events",
                    column: "payload_json"
                )
            }
            guard let data = payload.data(using: .utf8) else {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(
                    payload: payload,
                    reason: "payload is not valid UTF-8"
                )
            }
            do {
                return try decoder.decode(RuntimeEventDocument.self, from: data)
            } catch {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(
                    payload: payload,
                    reason: String(describing: error)
                )
            }
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
                .optionalText(event.status?.rawValue),
                .optionalText(event.previousStatus?.rawValue),
                .optionalText(event.operation?.rawValue),
                .text(event.message),
                .text(event.runtimeVersion),
                .text(payload),
            ]
        )
    }

    private func runtimeEventIndexStateValue(for key: String) throws -> String? {
        try database.withDatabase { db in
            try scalarString(
                db,
                sql: "SELECT value FROM runtime_event_index_state WHERE key = ? LIMIT 1",
                bindings: [.text(key)]
            )
        }
    }
}
