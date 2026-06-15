import Contracts
import SQLite3

struct SQLiteVitalDBRelationshipQueries {
    func loadBedAssignments(
        _ db: OpaquePointer,
        limit: Int
    ) throws -> [VitalDBBedAssignmentRecord] {
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

    func loadRelationshipEvents(
        _ db: OpaquePointer,
        limit: Int
    ) throws -> [VitalDBRelationshipEventRecord] {
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

    func openAssignment(
        for bedID: String,
        db: OpaquePointer
    ) throws -> VitalDBBedAssignmentRecord? {
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
}
