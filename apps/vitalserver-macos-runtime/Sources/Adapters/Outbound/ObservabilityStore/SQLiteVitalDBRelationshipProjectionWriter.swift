import Contracts
import SQLite3

struct SQLiteVitalDBRelationshipProjectionWriter {
    private let queries = SQLiteVitalDBRelationshipQueries()
    private let relationshipProjectionPlanner: VitalDBRelationshipProjectionPlanning

    init(
        relationshipProjectionPlanner: @escaping VitalDBRelationshipProjectionPlanning
    ) {
        self.relationshipProjectionPlanner = relationshipProjectionPlanner
    }

    func projectRelationships(
        _ observation: VitalDBObservationDocument,
        db: OpaquePointer
    ) throws {
        var openAssignmentsByBedID: [String: VitalDBBedAssignmentRecord] = [:]
        for bed in observation.beds.sorted(by: { $0.bedID < $1.bedID }) {
            openAssignmentsByBedID[bed.bedID] = try queries.openAssignment(for: bed.bedID, db: db)
        }

        let plan = relationshipProjectionPlanner(observation, openAssignmentsByBedID)
        for command in plan.assignmentCommands {
            try applyAssignmentCommand(command, db: db)
        }
        for event in plan.relationshipEvents {
            try insertRelationshipEvent(event, db: db)
        }
    }

    private func applyAssignmentCommand(
        _ command: VitalDBBedAssignmentProjectionCommand,
        db: OpaquePointer
    ) throws {
        switch command {
        case .insert(let insert):
            try insertAssignment(insert, db: db)
        case .update(let update):
            try updateAssignment(update, db: db)
        case .close(let close):
            try closeAssignment(close, db: db)
        }
    }

    private func insertAssignment(
        _ command: VitalDBBedAssignmentInsertCommand,
        db: OpaquePointer
    ) throws {
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
                .text(command.assignmentID),
                .text(command.bedID),
                .optionalText(command.bedName),
                .text(command.vrcode),
                .text(command.startedAt),
                .optionalText(command.lastSeenAt),
                .text(command.lastObservedAt),
                .text(command.status.rawValue),
                .optionalInt(command.patientConnected.map { $0 ? 1 : 0 }),
            ]
        )
    }

    private func updateAssignment(
        _ command: VitalDBBedAssignmentUpdateCommand,
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
                .optionalText(command.bedName),
                .optionalText(command.lastSeenAt),
                .text(command.lastObservedAt),
                .text(command.status.rawValue),
                .optionalInt(command.patientConnected.map { $0 ? 1 : 0 }),
                .text(command.assignmentID),
            ]
        )
    }

    private func closeAssignment(_ command: VitalDBBedAssignmentCloseCommand, db: OpaquePointer) throws {
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
                .text(command.endedAt),
                .text(command.endedAt),
                .text(command.assignmentID),
            ]
        )
    }

    private func insertRelationshipEvent(
        _ event: VitalDBRelationshipEventRecord,
        db: OpaquePointer
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
                .text(event.id),
                .text(event.observedAt),
                .text(event.eventType.rawValue),
                .text(event.severity.rawValue),
                .optionalText(event.bedID),
                .optionalText(event.bedName),
                .optionalText(event.vrcode),
                .optionalText(event.previousVrcode),
                .optionalText(event.previousBedID),
                .text(event.message),
            ]
        )
    }
}
