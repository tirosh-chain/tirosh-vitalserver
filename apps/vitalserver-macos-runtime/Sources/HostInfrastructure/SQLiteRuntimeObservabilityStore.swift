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
    public static let schemaVersion = 3

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
            return RuntimeEventPage(events: [])
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
                    try projectRelationships(observation, db: db)
                }
                try execute(db, sql: "COMMIT")
            } catch {
                try? execute(db, sql: "ROLLBACK")
                throw error
            }
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

    public func vitalDBBedAssignments(limit: Int = 1000) -> [VitalDBBedAssignmentRecord] {
        guard limit > 0 else {
            return []
        }
        do {
            try initialize()
            return try withDatabase { db in
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
        } catch {
            return []
        }
    }

    public func vitalDBRelationshipEvents(limit: Int = 1000) -> [VitalDBRelationshipEventRecord] {
        guard limit > 0 else {
            return []
        }
        do {
            try initialize()
            return try withDatabase { db in
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

    private func countRows(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)

        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
        }
        return Int(sqlite3_column_int64(statement, 0))
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

    private func vitalDBObservationExists(observedAt: String, db: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT 1 FROM vitaldb_observation_snapshots WHERE observed_at = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind([.text(observedAt)], to: statement, db: db)

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        guard result == SQLITE_DONE else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
        }
        return false
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

    private func projectRelationships(
        _ observation: VitalDBObservationDocument,
        db: OpaquePointer
    ) throws {
        let observedAt = observation.observedAt
        let recordersByVrcode = Dictionary(
            observation.recorders.map { ($0.vrcode, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let linkedBedVrcodes = Set(observation.beds.compactMap(\.vrcode).filter { !$0.isEmpty })
        let bedsByVrcode = Dictionary(grouping: observation.beds.compactMap { bed in
            bed.vrcode.map { ($0, bed) }
        }, by: \.0)

        for bed in observation.beds.sorted(by: { $0.bedID < $1.bedID }) {
            guard let vrcode = bed.vrcode, !vrcode.isEmpty else {
                try closeOpenAssignment(for: bed.bedID, endedAt: observedAt, db: db)
                try insertRelationshipEvent(
                    db,
                    id: relationshipEventID(.unlinkedBed, observedAt, bed.bedID, nil, nil),
                    observedAt: observedAt,
                    eventType: .unlinkedBed,
                    severity: .warning,
                    bedID: bed.bedID,
                    bedName: bed.name,
                    vrcode: nil,
                    previousVrcode: nil,
                    previousBedID: nil,
                    message: "Bed has no linked VRecorder."
                )
                continue
            }

            if let openAssignment = try openAssignment(for: bed.bedID, db: db) {
                if openAssignment.vrcode == vrcode {
                    try updateOpenAssignment(openAssignment, with: bed, observedAt: observedAt, db: db)
                } else {
                    try closeAssignment(openAssignment.id, endedAt: observedAt, db: db)
                    try insertRelationshipEvent(
                        db,
                        id: relationshipEventID(.handoff, observedAt, bed.bedID, vrcode, openAssignment.vrcode),
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

            if let recorder = recordersByVrcode[vrcode],
               bed.online != recorder.online {
                try insertRelationshipEvent(
                    db,
                    id: relationshipEventID(.staleLink, observedAt, bed.bedID, vrcode, nil),
                    observedAt: observedAt,
                    eventType: .staleLink,
                    severity: .warning,
                    bedID: bed.bedID,
                    bedName: bed.name,
                    vrcode: vrcode,
                    previousVrcode: nil,
                    previousBedID: nil,
                    message: "Bed and VRecorder online state differ."
                )
            }
        }

        for (vrcode, pairs) in bedsByVrcode where pairs.count > 1 {
            let bedIDs = pairs.map(\.1.bedID).sorted()
            try insertRelationshipEvent(
                db,
                id: relationshipEventID(.duplicateAssignment, observedAt, bedIDs.joined(separator: ","), vrcode, nil),
                observedAt: observedAt,
                eventType: .duplicateAssignment,
                severity: .warning,
                bedID: bedIDs.first,
                bedName: nil,
                vrcode: vrcode,
                previousVrcode: nil,
                previousBedID: nil,
                message: "VRecorder is linked to multiple beds: \(bedIDs.joined(separator: ", "))."
            )
        }

        for recorder in observation.recorders where !linkedBedVrcodes.contains(recorder.vrcode) {
            try insertRelationshipEvent(
                db,
                id: relationshipEventID(.unlinkedRecorder, observedAt, nil, recorder.vrcode, nil),
                observedAt: observedAt,
                eventType: .unlinkedRecorder,
                severity: recorder.online ? .warning : .info,
                bedID: nil,
                bedName: nil,
                vrcode: recorder.vrcode,
                previousVrcode: nil,
                previousBedID: nil,
                message: "VRecorder has no linked bed."
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
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)

        var assignments: [VitalDBBedAssignmentRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return assignments
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
            }
            guard let status = columnText(statement, 8) else {
                continue
            }
            assignments.append(VitalDBBedAssignmentRecord(
                id: columnText(statement, 0) ?? "",
                bedID: columnText(statement, 1) ?? "",
                bedName: columnText(statement, 2),
                vrcode: columnText(statement, 3) ?? "",
                startedAt: columnText(statement, 4) ?? "",
                endedAt: columnText(statement, 5),
                lastSeenAt: columnText(statement, 6),
                lastObservedAt: columnText(statement, 7) ?? "",
                status: status,
                patientConnected: columnOptionalBool(statement, 9),
                observationCount: Int(sqlite3_column_int64(statement, 10))
            ))
        }
    }

    private func queryRelationshipEvents(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBRelationshipEventRecord] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)

        var events: [VitalDBRelationshipEventRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return events
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(errorMessage(db))
            }
            guard let eventType = columnText(statement, 2).flatMap(VitalDBRelationshipEventType.init(rawValue:)),
                  let severity = columnText(statement, 3).flatMap(VitalDBRelationshipSeverity.init(rawValue:)) else {
                continue
            }
            events.append(VitalDBRelationshipEventRecord(
                id: columnText(statement, 0) ?? "",
                observedAt: columnText(statement, 1) ?? "",
                eventType: eventType,
                severity: severity,
                bedID: columnText(statement, 4),
                bedName: columnText(statement, 5),
                vrcode: columnText(statement, 6),
                previousVrcode: columnText(statement, 7),
                previousBedID: columnText(statement, 8),
                message: columnText(statement, 9) ?? ""
            ))
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
            case .optionalInt(let value):
                if let value {
                    result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
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
    case optionalInt(Int?)
}

private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let rawValue = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: rawValue)
}

private func columnOptionalBool(_ statement: OpaquePointer?, _ index: Int32) -> Bool? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }
    return sqlite3_column_int64(statement, index) != 0
}

private func assignmentID(bedID: String, vrcode: String, startedAt: String) -> String {
    "assignment:\(bedID):\(vrcode):\(startedAt)"
}

private func relationshipEventID(
    _ eventType: VitalDBRelationshipEventType,
    _ observedAt: String,
    _ bedID: String?,
    _ vrcode: String?,
    _ previous: String?
) -> String {
    [
        "relationship",
        eventType.rawValue,
        observedAt,
        bedID ?? "-",
        vrcode ?? "-",
        previous ?? "-",
    ].joined(separator: ":")
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
