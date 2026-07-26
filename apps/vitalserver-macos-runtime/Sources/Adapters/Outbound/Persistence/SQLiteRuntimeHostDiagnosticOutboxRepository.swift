import Application
import Contracts
import Foundation

public enum SQLiteRuntimeHostDiagnosticOutboxRepositoryError: Error, Equatable, CustomStringConvertible {
    case invalidField(field: String, value: String)
    case eventMissing(sequence: Int)
    case checkpointRegression(projection: String, current: Int, proposed: Int)
    case checkpointGap(projection: String, current: Int, proposed: Int)
    case operationFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidField(let field, let value):
            return "Host diagnostic projection field is invalid field=\(field) value=\(value)"
        case .eventMissing(let sequence):
            return "Host diagnostic outbox event is missing sequence=\(sequence)"
        case .checkpointRegression(let projection, let current, let proposed):
            return "Host diagnostic projection checkpoint regressed projection=\(projection) current=\(current) proposed=\(proposed)"
        case .checkpointGap(let projection, let current, let proposed):
            return "Host diagnostic projection checkpoint has a gap projection=\(projection) current=\(current) proposed=\(proposed)"
        case .operationFailed(let path, let reason):
            return "Host diagnostic projection SQLite operation failed path=\(path) reason=\(reason)"
        }
    }
}

public struct SQLiteRuntimeHostDiagnosticOutboxRepository:
    RuntimeHostDiagnosticOutboxRepository,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection

    public init(databaseURL: URL, busyTimeoutMilliseconds: Int32 = 5_000) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
    }

    public func loadPendingDiagnosticEvents(limit: Int) throws -> [RuntimeHostDiagnosticOutboxEvent] {
        guard limit > 0 else { throw invalid(field: "limit", value: String(limit)) }
        return try read { db in
            try SQLiteHostRuntimeStateStatement.stringRows(
                db,
                sql: """
                SELECT sequence, event_id, aggregate_type, aggregate_id,
                       aggregate_revision, event_type, occurred_at, payload_json
                FROM diagnostic_outbox
                WHERE projected_at IS NULL
                ORDER BY sequence ASC
                LIMIT ?
                """,
                bindings: [.int(limit)],
                columnCount: 8
            ).map(event)
        }
    }

    public func loadDiagnosticProjectionCheckpoint(
        projectionName: String
    ) throws -> RuntimeHostDiagnosticProjectionCheckpoint? {
        _ = try requireText(projectionName, field: "projection_name")
        return try read { db in
            guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
                db,
                sql: """
                SELECT projection_name, last_sequence, updated_at, failure_attempts, last_error
                FROM diagnostic_projection_state WHERE projection_name = ?
                """,
                bindings: [.text(projectionName)],
                columnCount: 5
            ) else { return nil }
            return try checkpoint(row)
        }
    }

    public func loadHostStateDiagnosticSnapshot(
        generatedAt: String
    ) throws -> RuntimeHostStateDiagnosticSnapshot {
        _ = try requireText(generatedAt, field: "generated_at")
        return try read { db in
            try connection.withDeferredReadTransaction(db) {
                let metadata = try loadMetadata(db)
                let sourceSequence = try SQLiteHostRuntimeStateStatement.scalarInt(
                    db,
                    sql: "SELECT COALESCE(MAX(sequence), 0) FROM diagnostic_outbox"
                ) ?? 0
                let lease = try loadLease(db)
                let lifecycle = try loadLifecycle(db)
                return RuntimeHostStateDiagnosticSnapshot(
                    databaseID: metadata.databaseID,
                    databaseSchemaVersion: metadata.schemaVersion,
                    sourceSequence: sourceSequence,
                    generatedAt: generatedAt,
                    operationLeaseState: lease?.state,
                    operationLease: lease?.document,
                    operationLeaseRevision: lease?.revision,
                    vmLifecycle: lifecycle?.document,
                    vmLifecycleRevision: lifecycle?.revision,
                    runtimeEndpoint: try loadEndpoint(db),
                    hostSettings: try loadSettings(db),
                    workflowOperations: try loadWorkflows(db)
                )
            }
        }
    }

    public func markDiagnosticEventProjected(
        sequence: Int,
        projectionName: String,
        projectedAt: String
    ) throws {
        try requirePositive(sequence, field: "sequence")
        _ = try requireText(projectionName, field: "projection_name")
        _ = try requireText(projectedAt, field: "projected_at")
        try write { db in
            let count = try SQLiteHostRuntimeStateStatement.scalarInt(
                db,
                sql: "SELECT COUNT(*) FROM diagnostic_outbox WHERE sequence = ?",
                bindings: [.int(sequence)]
            ) ?? 0
            guard count == 1 else { throw SQLiteRuntimeHostDiagnosticOutboxRepositoryError.eventMissing(sequence: sequence) }
            try advanceCheckpoint(
                db,
                name: projectionName,
                sequence: sequence,
                at: projectedAt,
                requiresContiguousSequence: true
            )
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                UPDATE diagnostic_outbox
                SET projected_at = COALESCE(projected_at, ?), last_projection_error = NULL
                WHERE sequence = ?
                """,
                bindings: [.text(projectedAt), .int(sequence)]
            )
        }
    }

    public func markDiagnosticSnapshotProjected(
        sourceSequence: Int,
        projectionName: String,
        projectedAt: String
    ) throws {
        guard sourceSequence >= 0 else { throw invalid(field: "source_sequence", value: String(sourceSequence)) }
        _ = try requireText(projectionName, field: "projection_name")
        _ = try requireText(projectedAt, field: "projected_at")
        try write { db in
            try advanceCheckpoint(
                db,
                name: projectionName,
                sequence: sourceSequence,
                at: projectedAt,
                requiresContiguousSequence: false
            )
        }
    }

    public func recordDiagnosticProjectionFailure(
        projectionName: String,
        sourceSequence: Int,
        reason: String,
        failedAt: String
    ) throws {
        guard sourceSequence >= 0 else { throw invalid(field: "source_sequence", value: String(sourceSequence)) }
        _ = try requireText(projectionName, field: "projection_name")
        _ = try requireText(reason, field: "reason")
        _ = try requireText(failedAt, field: "failed_at")
        try write { db in
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO diagnostic_projection_state(
                  projection_name, last_sequence, updated_at, failure_attempts, last_error
                ) VALUES (?, 0, ?, 1, ?)
                ON CONFLICT(projection_name) DO UPDATE SET
                  updated_at = excluded.updated_at,
                  failure_attempts = diagnostic_projection_state.failure_attempts + 1,
                  last_error = excluded.last_error
                """,
                bindings: [.text(projectionName), .text(failedAt), .text(reason)]
            )
            if projectionName == RuntimeHostDiagnosticProjectionNames.eventLog {
                try SQLiteHostRuntimeStateStatement.execute(
                    db,
                    sql: """
                    UPDATE diagnostic_outbox
                    SET projection_attempts = projection_attempts + 1,
                        last_projection_error = ?
                    WHERE sequence = ? AND projected_at IS NULL
                    """,
                    bindings: [.text(reason), .int(sourceSequence)]
                )
            }
        }
    }

    private func read<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                return try operation(db)
            }
        } catch let error as SQLiteRuntimeHostDiagnosticOutboxRepositoryError {
            throw error
        } catch {
            throw SQLiteRuntimeHostDiagnosticOutboxRepositoryError.operationFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func write(_ operation: (OpaquePointer) throws -> Void) throws {
        do {
            try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                try connection.withImmediateTransaction(db) { try operation(db) }
            }
        } catch let error as SQLiteRuntimeHostDiagnosticOutboxRepositoryError {
            throw error
        } catch {
            throw SQLiteRuntimeHostDiagnosticOutboxRepositoryError.operationFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func advanceCheckpoint(
        _ db: OpaquePointer,
        name: String,
        sequence: Int,
        at: String,
        requiresContiguousSequence: Bool
    ) throws {
        let current = try SQLiteHostRuntimeStateStatement.scalarInt(
            db,
            sql: "SELECT last_sequence FROM diagnostic_projection_state WHERE projection_name = ?",
            bindings: [.text(name)]
        ) ?? 0
        guard sequence >= current else {
            throw SQLiteRuntimeHostDiagnosticOutboxRepositoryError.checkpointRegression(
                projection: name,
                current: current,
                proposed: sequence
            )
        }
        if requiresContiguousSequence, sequence > current + 1 {
            throw SQLiteRuntimeHostDiagnosticOutboxRepositoryError.checkpointGap(
                projection: name,
                current: current,
                proposed: sequence
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO diagnostic_projection_state(
              projection_name, last_sequence, updated_at, failure_attempts, last_error
            ) VALUES (?, ?, ?, 0, NULL)
            ON CONFLICT(projection_name) DO UPDATE SET
              last_sequence = MAX(diagnostic_projection_state.last_sequence, excluded.last_sequence),
              updated_at = excluded.updated_at,
              failure_attempts = 0,
              last_error = NULL
            """,
            bindings: [.text(name), .int(sequence), .text(at)]
        )
    }

    private func event(_ row: [String?]) throws -> RuntimeHostDiagnosticOutboxEvent {
        RuntimeHostDiagnosticOutboxEvent(
            sequence: try positiveInt(row[0], field: "sequence"),
            eventID: try requireText(row[1], field: "event_id"),
            aggregateType: try requireText(row[2], field: "aggregate_type"),
            aggregateID: try requireText(row[3], field: "aggregate_id"),
            aggregateRevision: try positiveInt(row[4], field: "aggregate_revision"),
            eventType: try requireText(row[5], field: "event_type"),
            occurredAt: try requireText(row[6], field: "occurred_at"),
            payloadJSON: try requireText(row[7], field: "payload_json")
        )
    }

    private func checkpoint(_ row: [String?]) throws -> RuntimeHostDiagnosticProjectionCheckpoint {
        RuntimeHostDiagnosticProjectionCheckpoint(
            projectionName: try requireText(row[0], field: "projection_name"),
            lastSequence: try nonnegativeInt(row[1], field: "last_sequence"),
            updatedAt: try requireText(row[2], field: "updated_at"),
            failureAttempts: try nonnegativeInt(row[3], field: "failure_attempts"),
            lastError: row[4]
        )
    }

    private func loadMetadata(_ db: OpaquePointer) throws -> (schemaVersion: Int, databaseID: String) {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: "SELECT schema_version, database_id FROM runtime_metadata WHERE singleton_id = 1",
            columnCount: 2
        ) else { throw invalid(field: "runtime_metadata", value: "missing") }
        return (
            try positiveInt(row[0], field: "schema_version"),
            try requireText(row[1], field: "database_id")
        )
    }

    private func loadLease(
        _ db: OpaquePointer
    ) throws -> (state: String, revision: Int, document: RuntimeOperationLeaseDocument)? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT state, revision, document_schema_version, operation_id, operation,
                   owner_pid, started_at, heartbeat_at, expires_at, message
            FROM runtime_operation_lease WHERE singleton_id = 1
            """,
            columnCount: 10
        ) else { return nil }
        let operation = try knownOperation(row[4], field: "lease.operation")
        return (
            try requireText(row[0], field: "lease.state"),
            try positiveInt(row[1], field: "lease.revision"),
            RuntimeOperationLeaseDocument(
                schemaVersion: try positiveInt(row[2], field: "lease.schema_version"),
                operationId: try requireText(row[3], field: "lease.operation_id"),
                operation: operation,
                ownerPID: try optionalInt(row[5], field: "lease.owner_pid"),
                startedAt: try requireText(row[6], field: "lease.started_at"),
                heartbeatAt: try requireText(row[7], field: "lease.heartbeat_at"),
                expiresAt: row[8],
                message: row[9]
            )
        )
    }

    private func loadLifecycle(
        _ db: OpaquePointer
    ) throws -> (revision: Int, document: RuntimeVMLifecycleDocument)? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT revision, document_schema_version, run_id, state, operation,
                   operation_id, started_at, updated_at, deadline_at, terminal_reason, message
            FROM vm_lifecycle WHERE singleton_id = 1
            """,
            columnCount: 11
        ) else { return nil }
        let state = RuntimeVMLifecycleState(rawValue: try requireText(row[3], field: "lifecycle.state"))
        if case .unknown = state { throw invalid(field: "lifecycle.state", value: state.rawValue) }
        let reason = row[9].map(RuntimeVMLifecycleTerminalReason.init(rawValue:))
        if let reason, case .unknown = reason { throw invalid(field: "lifecycle.terminal_reason", value: reason.rawValue) }
        return (
            try positiveInt(row[0], field: "lifecycle.revision"),
            RuntimeVMLifecycleDocument(
                schemaVersion: try positiveInt(row[1], field: "lifecycle.schema_version"),
                state: state,
                operation: try knownOperation(row[4], field: "lifecycle.operation"),
                operationID: try requireText(row[5], field: "lifecycle.operation_id"),
                bootID: try requireText(row[2], field: "lifecycle.run_id"),
                startedAt: try requireText(row[6], field: "lifecycle.started_at"),
                updatedAt: try requireText(row[7], field: "lifecycle.updated_at"),
                deadlineAt: row[8],
                terminalReason: reason,
                message: row[10]
            )
        )
    }

    private func loadEndpoint(_ db: OpaquePointer) throws -> RuntimeEndpointDiagnosticSummary? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT revision, run_id, lifecycle_revision, address, source, observed_at
            FROM runtime_endpoint WHERE singleton_id = 1
            """,
            columnCount: 6
        ) else { return nil }
        return RuntimeEndpointDiagnosticSummary(
            revision: try positiveInt(row[0], field: "endpoint.revision"),
            runID: try requireText(row[1], field: "endpoint.run_id"),
            lifecycleRevision: try positiveInt(row[2], field: "endpoint.lifecycle_revision"),
            address: try requireText(row[3], field: "endpoint.address"),
            source: try requireText(row[4], field: "endpoint.source"),
            observedAt: try requireText(row[5], field: "endpoint.observed_at")
        )
    }

    private func loadSettings(_ db: OpaquePointer) throws -> RuntimeHostSettingsDiagnosticSummary? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT revision, desired_at, materialized_revision, materialized_at,
                   boot_revision, boot_run_id, boot_started_at,
                   applied_revision, applied_run_id, applied_at
            FROM host_runtime_settings WHERE singleton_id = 1
            """,
            columnCount: 10
        ) else { return nil }
        return RuntimeHostSettingsDiagnosticSummary(
            revision: try positiveInt(row[0], field: "settings.revision"),
            desiredAt: try requireText(row[1], field: "settings.desired_at"),
            materializedRevision: try optionalPositiveInt(row[2], field: "settings.materialized_revision"),
            materializedAt: row[3],
            bootRevision: try optionalPositiveInt(row[4], field: "settings.boot_revision"),
            bootRunID: row[5],
            bootStartedAt: row[6],
            appliedRevision: try optionalPositiveInt(row[7], field: "settings.applied_revision"),
            appliedRunID: row[8],
            appliedAt: row[9]
        )
    }

    private func loadWorkflows(_ db: OpaquePointer) throws -> [RuntimeWorkflowOperationDiagnosticSummary] {
        try SQLiteHostRuntimeStateStatement.stringRows(
            db,
            sql: """
            SELECT operation_id, operation_type, phase, current_step, step_status,
                   message, reason_codes_json, started_at, updated_at, completed_at, revision
            FROM workflow_operation_states ORDER BY updated_at DESC, operation_id ASC
            """,
            columnCount: 11
        ).map { row in
            let reasonData = Data(try requireText(row[6], field: "workflow.reason_codes_json").utf8)
            let reasons = try JSONDecoder().decode([String].self, from: reasonData)
            let phase = RuntimeProgressPhase(rawValue: try requireText(row[2], field: "workflow.phase"))
            if case .unknown = phase { throw invalid(field: "workflow.phase", value: phase.rawValue) }
            let currentStep = row[3].map(RuntimeWorkflowStep.init(rawValue:))
            if let currentStep, case .unknown = currentStep {
                throw invalid(field: "workflow.current_step", value: currentStep.rawValue)
            }
            let stepStatus = row[4].map(RuntimeProgressStepStatus.init(rawValue:))
            if let stepStatus, case .unknown = stepStatus {
                throw invalid(field: "workflow.step_status", value: stepStatus.rawValue)
            }
            return RuntimeWorkflowOperationDiagnosticSummary(
                operationID: try requireText(row[0], field: "workflow.operation_id"),
                operation: try knownOperation(row[1], field: "workflow.operation"),
                phase: phase,
                currentStep: currentStep,
                stepStatus: stepStatus,
                message: try requireText(row[5], field: "workflow.message"),
                reasonCodes: reasons,
                startedAt: try requireText(row[7], field: "workflow.started_at"),
                updatedAt: try requireText(row[8], field: "workflow.updated_at"),
                completedAt: row[9],
                revision: try positiveInt(row[10], field: "workflow.revision")
            )
        }
    }

    private func knownOperation(_ value: String?, field: String) throws -> RuntimeOperation {
        let operation = RuntimeOperation(rawValue: try requireText(value, field: field))
        if case .unknown = operation { throw invalid(field: field, value: operation.rawValue) }
        return operation
    }

    private func requireText(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else { throw invalid(field: field, value: value ?? "NULL") }
        return value
    }

    private func requirePositive(_ value: Int, field: String) throws {
        guard value > 0 else { throw invalid(field: field, value: String(value)) }
    }

    private func positiveInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value), parsed > 0 else { throw invalid(field: field, value: value ?? "NULL") }
        return parsed
    }

    private func nonnegativeInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value), parsed >= 0 else { throw invalid(field: field, value: value ?? "NULL") }
        return parsed
    }

    private func optionalPositiveInt(_ value: String?, field: String) throws -> Int? {
        guard value != nil else { return nil }
        return try positiveInt(value, field: field)
    }

    private func optionalInt(_ value: String?, field: String) throws -> Int? {
        guard let value else { return nil }
        guard let parsed = Int(value) else { throw invalid(field: field, value: value) }
        return parsed
    }

    private func invalid(field: String, value: String) -> SQLiteRuntimeHostDiagnosticOutboxRepositoryError {
        .invalidField(field: field, value: value)
    }
}
