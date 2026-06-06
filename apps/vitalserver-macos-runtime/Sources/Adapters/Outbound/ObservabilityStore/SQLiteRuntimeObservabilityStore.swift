import Foundation
import SQLite3
import Contracts
import Application
import Errors

public struct SQLiteRuntimeObservabilityStore {
    public static let schemaVersion = 4

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
            CREATE TABLE IF NOT EXISTS runtime_event_index_state (
              key text primary key,
              value text not null
            )
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
            try execute(db, sql: """
            CREATE TABLE IF NOT EXISTS vitaldb_recorder_activity_buckets (
              vrcode text not null,
              bucket_started_at text not null,
              bucket_seconds integer not null,
              message_count integer not null,
              byte_count integer not null,
              room_count integer not null,
              first_observed_at text not null,
              last_observed_at text not null,
              primary key(vrcode, bucket_started_at, bucket_seconds)
            )
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_recorder_activity_buckets_time
              ON vitaldb_recorder_activity_buckets(bucket_started_at)
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_recorder_activity_buckets_vrcode_time
              ON vitaldb_recorder_activity_buckets(vrcode, bucket_started_at)
            """)
            try execute(db, sql: """
            CREATE TABLE IF NOT EXISTS vitaldb_bed_assignments (
              id text primary key,
              bed_id text not null,
              bed_name text,
              vrcode text not null,
              started_at text not null,
              ended_at text,
              last_seen_at text,
              last_observed_at text not null,
              status text not null,
              patient_connected integer,
              observation_count integer not null
            )
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_bed_assignments_bed_time
              ON vitaldb_bed_assignments(bed_id, started_at)
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_bed_assignments_vrcode_time
              ON vitaldb_bed_assignments(vrcode, started_at)
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_bed_assignments_open
              ON vitaldb_bed_assignments(bed_id, ended_at)
            """)
            try execute(db, sql: """
            CREATE TABLE IF NOT EXISTS vitaldb_relationship_events (
              id text primary key,
              observed_at text not null,
              event_type text not null,
              severity text not null,
              bed_id text,
              bed_name text,
              vrcode text,
              previous_vrcode text,
              previous_bed_id text,
              message text not null
            )
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_relationship_events_observed_at
              ON vitaldb_relationship_events(observed_at)
            """)
            try execute(db, sql: """
            CREATE INDEX IF NOT EXISTS idx_vitaldb_relationship_events_type_time
              ON vitaldb_relationship_events(event_type, observed_at)
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

    public func upsertRuntimeEvents(_ events: [RuntimeEventDocument]) throws {
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

    public func runtimeEventIndexCatchUpDue(now: Date, intervalSeconds: TimeInterval) -> Bool {
        do {
            try initialize()
            let lastCaughtUpAt = try runtimeEventIndexStateValue(for: "last_caught_up_at")
            guard let lastCaughtUpAt,
                  let lastCaughtUpAtSeconds = TimeInterval(lastCaughtUpAt) else {
                return true
            }
            return now.timeIntervalSince1970 - lastCaughtUpAtSeconds >= intervalSeconds
        } catch {
            return true
        }
    }

    public func markRuntimeEventIndexCaughtUp(at date: Date) throws {
        try initialize()
        try withDatabase { db in
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
            return try withReadOnlyDatabase { db in
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
            return RuntimeEventPage(events: [], readError: String(describing: error))
        }
    }

    public func append(_ observation: VitalDBObservationDocument) throws {
        try initialize()
        try withDatabase { db in
            try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                let shouldProject = try !vitalDBObservationExists(observedAt: observation.observedAt, db: db)
                try insert(observation, db: db)
                if shouldProject {
                    try projectRecorderActivityBuckets(observation, db: db)
                    try projectRelationships(observation, db: db)
                }
                try execute(db, sql: "COMMIT")
            } catch {
                try? execute(db, sql: "ROLLBACK")
                throw error
            }
        }
    }

    public func loadLatestVitalDBObservation() throws -> VitalDBObservationDocument? {
        try withReadOnlyDatabase { db in
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
    }

    public func loadVitalDBObservations(limit: Int = 1000) throws -> [VitalDBObservationDocument] {
        guard limit > 0 else {
            return []
        }
        return try withReadOnlyDatabase { db in
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
    }

    public func loadVitalDBRecorderActivityBuckets(
        query: VitalDBRecorderActivityBucketQuery = VitalDBRecorderActivityBucketQuery()
    ) throws -> [VitalDBRecorderActivityBucketRecord] {
        guard query.limit > 0 else {
            return []
        }
        return try withReadOnlyDatabase { db in
            var predicates: [String] = []
            var bindings: [SQLiteBinding] = []
            if let vrcode = query.vrcode {
                predicates.append("vrcode = ?")
                bindings.append(.text(vrcode))
            }
            if let since = query.since {
                predicates.append("bucket_started_at >= ?")
                bindings.append(.text(since))
            }
            if let until = query.until {
                predicates.append("bucket_started_at <= ?")
                bindings.append(.text(until))
            }
            let whereClause = predicates.isEmpty ? "" : "WHERE \(predicates.joined(separator: " AND "))"
            bindings.append(.int(query.limit))
            let records = try queryRecorderActivityBuckets(
                db,
                sql: """
                SELECT vrcode, bucket_started_at, bucket_seconds,
                       message_count, byte_count, room_count,
                       first_observed_at, last_observed_at
                FROM vitaldb_recorder_activity_buckets
                \(whereClause)
                ORDER BY bucket_started_at DESC, vrcode DESC
                LIMIT ?
                """,
                bindings: bindings
            )
            return Array(records.reversed())
        }
    }

    public func loadVitalDBBedAssignments(limit: Int = 1000) throws -> [VitalDBBedAssignmentRecord] {
        guard limit > 0 else {
            return []
        }
        return try withReadOnlyDatabase { db in
            try queryBedAssignments(
                db,
                sql: """
                SELECT id, bed_id, bed_name, vrcode, started_at, ended_at,
                       last_seen_at, last_observed_at, status, patient_connected,
                       observation_count
                FROM vitaldb_bed_assignments
                ORDER BY started_at DESC, id DESC
                LIMIT ?
                """,
                bindings: [.int(limit)]
            )
        }
    }

    public func loadVitalDBRelationshipEvents(limit: Int = 1000) throws -> [VitalDBRelationshipEventRecord] {
        guard limit > 0 else {
            return []
        }
        return try withReadOnlyDatabase { db in
            Array(try queryRelationshipEvents(
                db,
                sql: """
                SELECT id, observed_at, event_type, severity, bed_id, bed_name,
                       vrcode, previous_vrcode, previous_bed_id, message
                FROM vitaldb_relationship_events
                ORDER BY observed_at DESC, id DESC
                LIMIT ?
                """,
                bindings: [.int(limit)]
            ).reversed())
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
            let payload = try requiredText(statement, 0, table: "runtime_events", column: "payload_json")
            guard let data = payload.data(using: .utf8),
                  let event = try? decoder.decode(RuntimeEventDocument.self, from: data) else {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(payload)
            }
            return event
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
        try withDatabase { db in
            try scalarString(
                db,
                sql: "SELECT value FROM runtime_event_index_state WHERE key = ? LIMIT 1",
                bindings: [.text(key)]
            )
        }
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

    private func vitalDBObservationExists(observedAt: String, db: OpaquePointer) throws -> Bool {
        try containsRow(
            db,
            sql: "SELECT 1 FROM vitaldb_observation_snapshots WHERE observed_at = ? LIMIT 1",
            bindings: [.text(observedAt)]
        )
    }

    private func projectRecorderActivityBuckets(
        _ observation: VitalDBObservationDocument,
        db: OpaquePointer
    ) throws {
        for recorder in observation.recorders {
            guard let activity = recorder.activity else {
                continue
            }
            for bucket in activity.buckets {
                try upsertRecorderActivityBucket(
                    vrcode: recorder.vrcode,
                    bucket: bucket,
                    observedAt: observation.observedAt,
                    db: db
                )
            }
        }
    }

    private func upsertRecorderActivityBucket(
        vrcode: String,
        bucket: VitalDBRecorderActivityBucket,
        observedAt: String,
        db: OpaquePointer
    ) throws {
        try execute(
            db,
            sql: """
            INSERT INTO vitaldb_recorder_activity_buckets(
              vrcode,
              bucket_started_at,
              bucket_seconds,
              message_count,
              byte_count,
              room_count,
              first_observed_at,
              last_observed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(vrcode, bucket_started_at, bucket_seconds) DO UPDATE SET
              message_count = max(message_count, excluded.message_count),
              byte_count = max(byte_count, excluded.byte_count),
              room_count = max(room_count, excluded.room_count),
              first_observed_at = min(first_observed_at, excluded.first_observed_at),
              last_observed_at = max(last_observed_at, excluded.last_observed_at)
            """,
            bindings: [
                .text(vrcode),
                .text(bucket.bucketStartedAt),
                .int(bucket.bucketSeconds),
                .int(bucket.messageCount),
                .int(bucket.byteCount),
                .int(bucket.roomCount),
                .text(observedAt),
                .text(observedAt),
            ]
        )
    }

    private func queryVitalDBObservations(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBObservationDocument] {
        let decoder = JSONDecoder()
        return try queryRows(db, sql: sql, bindings: bindings) { statement in
            let payload = try requiredText(
                statement,
                0,
                table: "vitaldb_observation_snapshots",
                column: "payload_json"
            )
            guard let data = payload.data(using: .utf8),
                  let observation = try? decoder.decode(VitalDBObservationDocument.self, from: data) else {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(payload)
            }
            return observation
        }
    }

    private func queryRecorderActivityBuckets(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBRecorderActivityBucketRecord] {
        try queryRows(db, sql: sql, bindings: bindings) { statement in
            let vrcode = try requiredText(statement, 0, table: "vitaldb_recorder_activity_buckets", column: "vrcode")
            let bucketStartedAt = try requiredText(
                statement,
                1,
                table: "vitaldb_recorder_activity_buckets",
                column: "bucket_started_at"
            )
            let firstObservedAt = try requiredText(
                statement,
                6,
                table: "vitaldb_recorder_activity_buckets",
                column: "first_observed_at"
            )
            let lastObservedAt = try requiredText(
                statement,
                7,
                table: "vitaldb_recorder_activity_buckets",
                column: "last_observed_at"
            )
            return VitalDBRecorderActivityBucketRecord(
                vrcode: vrcode,
                bucketStartedAt: bucketStartedAt,
                bucketSeconds: Int(sqlite3_column_int(statement, 2)),
                messageCount: Int(sqlite3_column_int(statement, 3)),
                byteCount: Int(sqlite3_column_int(statement, 4)),
                roomCount: Int(sqlite3_column_int(statement, 5)),
                firstObservedAt: firstObservedAt,
                lastObservedAt: lastObservedAt
            )
        }
    }

    private func projectRelationships(
        _ observation: VitalDBObservationDocument,
        db: OpaquePointer
    ) throws {
        let observedAt = observation.observedAt
        let plannedEvents = VitalDBRelationshipProjectionPlanner().plannedEvents(for: observation)

        for bed in observation.beds.sorted(by: { $0.bedID < $1.bedID }) {
            guard let vrcode = bed.vrcode, !vrcode.isEmpty else {
                try closeOpenAssignment(for: bed.bedID, endedAt: observedAt, db: db)
                continue
            }

            if let openAssignment = try openAssignment(for: bed.bedID, db: db) {
                if openAssignment.vrcode == vrcode {
                    try updateOpenAssignment(openAssignment, with: bed, observedAt: observedAt, db: db)
                } else {
                    try closeAssignment(openAssignment.id, endedAt: observedAt, db: db)
                    try insertRelationshipEvent(
                        db,
                        id: VitalDBRelationshipProjectionPlanner.eventID(
                            .handoff,
                            observedAt,
                            bed.bedID,
                            vrcode,
                            openAssignment.vrcode
                        ),
                        observedAt: observedAt,
                        eventType: .handoff,
                        severity: .info,
                        bedID: bed.bedID,
                        bedName: bed.name,
                        vrcode: vrcode,
                        previousVrcode: openAssignment.vrcode,
                        previousBedID: nil,
                        message: "Bed VRecorder assignment changed."
                    )
                    try insertAssignment(for: bed, observedAt: observedAt, db: db)
                }
            } else {
                try insertAssignment(for: bed, observedAt: observedAt, db: db)
            }
        }

        for event in plannedEvents {
            try insertRelationshipEvent(
                db,
                id: event.id,
                observedAt: event.observedAt,
                eventType: event.eventType,
                severity: event.severity,
                bedID: event.bedID,
                bedName: event.bedName,
                vrcode: event.vrcode,
                previousVrcode: event.previousVrcode,
                previousBedID: event.previousBedID,
                message: event.message
            )
        }
    }

    private func openAssignment(for bedID: String, db: OpaquePointer) throws -> VitalDBBedAssignmentRecord? {
        try queryBedAssignments(
            db,
            sql: """
            SELECT id, bed_id, bed_name, vrcode, started_at, ended_at,
                   last_seen_at, last_observed_at, status, patient_connected,
                   observation_count
            FROM vitaldb_bed_assignments
            WHERE bed_id = ? AND ended_at IS NULL
            ORDER BY started_at DESC, id DESC
            LIMIT 1
            """,
            bindings: [.text(bedID)]
        ).first
    }

    private func insertAssignment(
        for bed: VitalDBBedObservation,
        observedAt: String,
        db: OpaquePointer
    ) throws {
        guard let vrcode = bed.vrcode, !vrcode.isEmpty else {
            return
        }
        try execute(
            db,
            sql: """
            INSERT OR REPLACE INTO vitaldb_bed_assignments(
              id,
              bed_id,
              bed_name,
              vrcode,
              started_at,
              ended_at,
              last_seen_at,
              last_observed_at,
              status,
              patient_connected,
              observation_count
            ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, 1)
            """,
            bindings: [
                .text(assignmentID(bedID: bed.bedID, vrcode: vrcode, startedAt: observedAt)),
                .text(bed.bedID),
                .optionalText(bed.name),
                .text(vrcode),
                .text(observedAt),
                .optionalText(bed.lastSeenAt),
                .text(observedAt),
                .text(bed.online ? "online" : "stale"),
                .optionalInt(bed.patientConnected.map { $0 ? 1 : 0 }),
            ]
        )
    }

    private func updateOpenAssignment(
        _ assignment: VitalDBBedAssignmentRecord,
        with bed: VitalDBBedObservation,
        observedAt: String,
        db: OpaquePointer
    ) throws {
        try execute(
            db,
            sql: """
            UPDATE vitaldb_bed_assignments
            SET bed_name = COALESCE(?, bed_name),
                last_seen_at = ?,
                last_observed_at = ?,
                status = ?,
                patient_connected = ?,
                observation_count = observation_count + 1
            WHERE id = ?
            """,
            bindings: [
                .optionalText(bed.name),
                .optionalText(bed.lastSeenAt),
                .text(observedAt),
                .text(bed.online ? "online" : "stale"),
                .optionalInt(bed.patientConnected.map { $0 ? 1 : 0 }),
                .text(assignment.id),
            ]
        )
    }

    private func closeOpenAssignment(for bedID: String, endedAt: String, db: OpaquePointer) throws {
        if let openAssignment = try openAssignment(for: bedID, db: db) {
            try closeAssignment(openAssignment.id, endedAt: endedAt, db: db)
        }
    }

    private func closeAssignment(_ id: String, endedAt: String, db: OpaquePointer) throws {
        try execute(
            db,
            sql: """
            UPDATE vitaldb_bed_assignments
            SET ended_at = ?,
                last_observed_at = ?,
                status = 'offline'
            WHERE id = ? AND ended_at IS NULL
            """,
            bindings: [
                .text(endedAt),
                .text(endedAt),
                .text(id),
            ]
        )
    }

    private func insertRelationshipEvent(
        _ db: OpaquePointer,
        id: String,
        observedAt: String,
        eventType: VitalDBRelationshipEventType,
        severity: VitalDBRelationshipSeverity,
        bedID: String?,
        bedName: String?,
        vrcode: String?,
        previousVrcode: String?,
        previousBedID: String?,
        message: String
    ) throws {
        try execute(
            db,
            sql: """
            INSERT OR REPLACE INTO vitaldb_relationship_events(
              id,
              observed_at,
              event_type,
              severity,
              bed_id,
              bed_name,
              vrcode,
              previous_vrcode,
              previous_bed_id,
              message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(id),
                .text(observedAt),
                .text(eventType.rawValue),
                .text(severity.rawValue),
                .optionalText(bedID),
                .optionalText(bedName),
                .optionalText(vrcode),
                .optionalText(previousVrcode),
                .optionalText(previousBedID),
                .text(message),
            ]
        )
    }

    private func queryBedAssignments(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBBedAssignmentRecord] {
        try queryRows(db, sql: sql, bindings: bindings) { statement in
            let id = try requiredText(statement, 0, table: "vitaldb_bed_assignments", column: "id")
            let bedID = try requiredText(statement, 1, table: "vitaldb_bed_assignments", column: "bed_id")
            let vrcode = try requiredText(statement, 3, table: "vitaldb_bed_assignments", column: "vrcode")
            let startedAt = try requiredText(statement, 4, table: "vitaldb_bed_assignments", column: "started_at")
            let lastObservedAt = try requiredText(
                statement,
                7,
                table: "vitaldb_bed_assignments",
                column: "last_observed_at"
            )
            let status = try requiredEnum(
                VitalDBBedAssignmentStatus.self,
                statement,
                8,
                table: "vitaldb_bed_assignments",
                column: "status"
            )
            return VitalDBBedAssignmentRecord(
                id: id,
                bedID: bedID,
                bedName: columnText(statement, 2),
                vrcode: vrcode,
                startedAt: startedAt,
                endedAt: columnText(statement, 5),
                lastSeenAt: columnText(statement, 6),
                lastObservedAt: lastObservedAt,
                status: status,
                patientConnected: columnOptionalBool(statement, 9),
                observationCount: Int(sqlite3_column_int64(statement, 10))
            )
        }
    }

    private func queryRelationshipEvents(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBRelationshipEventRecord] {
        try queryRows(db, sql: sql, bindings: bindings) { statement in
            let id = try requiredText(statement, 0, table: "vitaldb_relationship_events", column: "id")
            let observedAt = try requiredText(
                statement,
                1,
                table: "vitaldb_relationship_events",
                column: "observed_at"
            )
            let eventType = try requiredEnum(
                VitalDBRelationshipEventType.self,
                statement,
                2,
                table: "vitaldb_relationship_events",
                column: "event_type"
            )
            let severity = try requiredEnum(
                VitalDBRelationshipSeverity.self,
                statement,
                3,
                table: "vitaldb_relationship_events",
                column: "severity"
            )
            let message = try requiredText(statement, 9, table: "vitaldb_relationship_events", column: "message")
            return VitalDBRelationshipEventRecord(
                id: id,
                observedAt: observedAt,
                eventType: eventType,
                severity: severity,
                bedID: columnText(statement, 4),
                bedName: columnText(statement, 5),
                vrcode: columnText(statement, 6),
                previousVrcode: columnText(statement, 7),
                previousBedID: columnText(statement, 8),
                message: message
            )
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
            let message = db.map(sqliteErrorMessage) ?? "unknown sqlite open error"
            sqlite3_close(db)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedDB)
        }
        return try operation(openedDB)
    }

    private func withReadOnlyDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let openedDB = db else {
            let message = db.map(sqliteErrorMessage) ?? "unknown sqlite open error"
            sqlite3_close(db)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedDB)
        }
        return try operation(openedDB)
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private func assignmentID(bedID: String, vrcode: String, startedAt: String) -> String {
    "assignment:\(bedID):\(vrcode):\(startedAt)"
}

private func requiredText(
    _ statement: OpaquePointer?,
    _ index: Int32,
    table: String,
    column: String
) throws -> String {
    guard let value = columnText(statement, index) else {
        throw SQLiteRuntimeObservabilityStoreError.missingColumn(table: table, column: column)
    }
    return value
}

private func requiredEnum<T: RawRepresentable>(
    _ type: T.Type,
    _ statement: OpaquePointer?,
    _ index: Int32,
    table: String,
    column: String
) throws -> T where T.RawValue == String {
    let value = try requiredText(statement, index, table: table, column: column)
    guard let decoded = type.init(rawValue: value) else {
        throw SQLiteRuntimeObservabilityStoreError.invalidColumnValue(
            table: table,
            column: column,
            value: value
        )
    }
    return decoded
}
