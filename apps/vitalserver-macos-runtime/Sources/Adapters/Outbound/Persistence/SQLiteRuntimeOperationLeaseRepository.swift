import Application
import Contracts
import Errors
import Foundation

public struct SQLiteRuntimeOperationLeaseRepository:
    RuntimeOperationLeaseOwner,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let eventID: @Sendable () -> String
    private let timestamp: @Sendable () -> String
    private let encoder: JSONEncoder

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        eventID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        timestamp: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        },
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.eventID = eventID
        self.timestamp = timestamp
        self.encoder = encoder
    }

    public func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                switch try loadStoredLease(db) {
                case .missing, .released:
                    return .missing
                case .active(_, let document):
                    return .loaded(document)
                }
            }
        } catch {
            return .failed(
                "runtime operation lease SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    public func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        try mutate { db in
            let priorRevision: Int
            switch try loadStoredLease(db) {
            case .missing:
                priorRevision = 0
            case .released(let revision, _):
                priorRevision = revision
            case .active(_, let existing):
                throw RuntimeOperationLeaseOwnerError.existingOperation(
                    operationId: existing.operationId,
                    operation: existing.operation.rawValue
                )
            }

            let revision = priorRevision + 1
            let occurredAt = timestamp()
            try writeLease(
                db,
                revision: revision,
                state: .active,
                document: document,
                updatedAt: occurredAt
            )
            try appendDiagnosticEvent(
                db,
                revision: revision,
                eventType: "operation-lease-acquired",
                occurredAt: occurredAt,
                state: .active,
                document: document
            )
        }
    }

    public func heartbeat(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) throws {
        try mutate { db in
            guard case .active(let priorRevision, let existing) = try loadStoredLease(db) else {
                throw RuntimeOperationLeaseOwnerError.readFailed(
                    "runtime operation lease is missing during heartbeat"
                )
            }
            guard existing.operationId == operationId else {
                throw RuntimeOperationLeaseOwnerError.operationIdMismatch(
                    expected: operationId,
                    actual: existing.operationId
                )
            }

            let updated = RuntimeOperationLeaseDocument(
                schemaVersion: existing.schemaVersion,
                operationId: existing.operationId,
                operation: existing.operation,
                targetInstallationId: existing.targetInstallationId,
                expectedInstallationRevision: existing.expectedInstallationRevision,
                ownerPID: existing.ownerPID,
                startedAt: existing.startedAt,
                heartbeatAt: heartbeatAt,
                expiresAt: expiresAt,
                message: existing.message
            )
            let revision = priorRevision + 1
            let occurredAt = timestamp()
            try writeLease(
                db,
                revision: revision,
                state: .active,
                document: updated,
                updatedAt: occurredAt
            )
            try appendDiagnosticEvent(
                db,
                revision: revision,
                eventType: "operation-lease-heartbeat",
                occurredAt: occurredAt,
                state: .active,
                document: updated
            )
        }
    }

    public func release(operationId: String) throws {
        try mutate { db in
            switch try loadStoredLease(db) {
            case .missing, .released:
                return
            case .active(let priorRevision, let existing):
                guard existing.operationId == operationId else {
                    throw RuntimeOperationLeaseOwnerError.operationIdMismatch(
                        expected: operationId,
                        actual: existing.operationId
                    )
                }
                let revision = priorRevision + 1
                let occurredAt = timestamp()
                try writeLease(
                    db,
                    revision: revision,
                    state: .released,
                    document: existing,
                    updatedAt: occurredAt
                )
                try appendDiagnosticEvent(
                    db,
                    revision: revision,
                    eventType: "operation-lease-released",
                    occurredAt: occurredAt,
                    state: .released,
                    document: existing
                )
            }
        }
    }

    func loadLegacyImportRecord(
        migrationID: String
    ) throws -> SQLiteRuntimeOperationLeaseLegacyImportRecord? {
        try connection.withReadOnlyDatabase { db in
            _ = try SQLiteHostRuntimeStateSchema.validate(db)
            guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
                db,
                sql: """
                SELECT source_state, source_operation_id
                FROM legacy_state_imports
                WHERE migration_id = ?
                """,
                bindings: [.text(migrationID)],
                columnCount: 2
            ) else {
                return nil
            }
            guard let stateValue = row[0],
                  let state = SQLiteRuntimeOperationLeaseLegacyImportState(rawValue: stateValue) else {
                throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                    field: "legacy_state_imports.source_state",
                    value: row[0] ?? "NULL"
                )
            }
            if state == .missing, row[1] != nil {
                throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                    field: "legacy_state_imports.source_operation_id",
                    value: row[1] ?? "NULL"
                )
            }
            if state == .imported, row[1]?.isEmpty != false {
                throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                    field: "legacy_state_imports.source_operation_id",
                    value: row[1] ?? "NULL"
                )
            }
            return SQLiteRuntimeOperationLeaseLegacyImportRecord(
                state: state,
                operationID: row[1]
            )
        }
    }

    func recordMissingLegacySource(
        migrationID: String,
        sourcePath: String,
        completedAt: String
    ) throws {
        try mutate { db in
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO legacy_state_imports(
                  migration_id,
                  source_path,
                  source_state,
                  source_operation_id,
                  completed_at
                ) VALUES (?, ?, 'missing', NULL, ?)
                """,
                bindings: [
                    .text(migrationID),
                    .text(sourcePath),
                    .text(completedAt),
                ]
            )
        }
    }

    func importLegacyDocument(
        _ document: RuntimeOperationLeaseDocument,
        migrationID: String,
        sourcePath: String,
        completedAt: String
    ) throws {
        try mutate { db in
            let priorRevision: Int
            switch try loadStoredLease(db) {
            case .missing:
                priorRevision = 0
            case .released(let revision, _):
                priorRevision = revision
            case .active(_, let existing):
                throw RuntimeOperationLeaseOwnerError.existingOperation(
                    operationId: existing.operationId,
                    operation: existing.operation.rawValue
                )
            }

            let revision = priorRevision + 1
            try writeLease(
                db,
                revision: revision,
                state: .active,
                document: document,
                updatedAt: completedAt
            )
            try appendDiagnosticEvent(
                db,
                revision: revision,
                eventType: "operation-lease-legacy-imported",
                occurredAt: completedAt,
                state: .active,
                document: document
            )
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO legacy_state_imports(
                  migration_id,
                  source_path,
                  source_state,
                  source_operation_id,
                  completed_at
                ) VALUES (?, ?, 'imported', ?, ?)
                """,
                bindings: [
                    .text(migrationID),
                    .text(sourcePath),
                    .text(document.operationId),
                    .text(completedAt),
                ]
            )
        }
    }

    private func mutate(_ operation: (OpaquePointer) throws -> Void) throws {
        do {
            try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                try connection.withImmediateTransaction(db) {
                    try operation(db)
                }
            }
        } catch let error as RuntimeOperationLeaseOwnerError {
            throw error
        } catch {
            throw RuntimeOperationLeaseOwnerError.writeFailed(
                "path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    private func loadStoredLease(_ db: OpaquePointer) throws -> StoredLease {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT
              revision,
              state,
              document_schema_version,
              operation_id,
              operation,
              owner_pid,
              started_at,
              heartbeat_at,
              expires_at,
              message,
              target_installation_id,
              expected_installation_revision
            FROM runtime_operation_lease
            WHERE singleton_id = 1
            """,
            columnCount: 12
        ) else {
            return .missing
        }

        let revision = try requiredInt(row[0], field: "revision")
        let state = try requiredState(row[1])
        let document = RuntimeOperationLeaseDocument(
            schemaVersion: try requiredInt(row[2], field: "document_schema_version"),
            operationId: try requiredText(row[3], field: "operation_id"),
            operation: RuntimeOperation(rawValue: try requiredText(row[4], field: "operation")),
            targetInstallationId: row[10],
            expectedInstallationRevision: try optionalInt(
                row[11],
                field: "expected_installation_revision"
            ),
            ownerPID: try optionalInt(row[5], field: "owner_pid"),
            startedAt: try requiredText(row[6], field: "started_at"),
            heartbeatAt: try requiredText(row[7], field: "heartbeat_at"),
            expiresAt: row[8],
            message: row[9]
        )
        switch state {
        case .active:
            return .active(revision: revision, document: document)
        case .released:
            return .released(revision: revision, document: document)
        }
    }

    private func writeLease(
        _ db: OpaquePointer,
        revision: Int,
        state: StoredLeaseState,
        document: RuntimeOperationLeaseDocument,
        updatedAt: String
    ) throws {
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO runtime_operation_lease(
              singleton_id,
              revision,
              state,
              document_schema_version,
              operation_id,
              operation,
              owner_pid,
              started_at,
              heartbeat_at,
              expires_at,
              message,
              target_installation_id,
              expected_installation_revision,
              updated_at
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(singleton_id) DO UPDATE SET
              revision = excluded.revision,
              state = excluded.state,
              document_schema_version = excluded.document_schema_version,
              operation_id = excluded.operation_id,
              operation = excluded.operation,
              owner_pid = excluded.owner_pid,
              started_at = excluded.started_at,
              heartbeat_at = excluded.heartbeat_at,
              expires_at = excluded.expires_at,
              message = excluded.message,
              target_installation_id = excluded.target_installation_id,
              expected_installation_revision = excluded.expected_installation_revision,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .int(revision),
                .text(state.rawValue),
                .int(document.schemaVersion),
                .text(document.operationId),
                .text(document.operation.rawValue),
                .optionalInt(document.ownerPID),
                .text(document.startedAt),
                .text(document.heartbeatAt),
                .optionalText(document.expiresAt),
                .optionalText(document.message),
                .optionalText(document.targetInstallationId),
                .optionalInt(document.expectedInstallationRevision),
                .text(updatedAt),
            ]
        )
    }

    private func appendDiagnosticEvent(
        _ db: OpaquePointer,
        revision: Int,
        eventType: String,
        occurredAt: String,
        state: StoredLeaseState,
        document: RuntimeOperationLeaseDocument
    ) throws {
        let payload = try String(
            decoding: encoder.encode(OperationLeaseDiagnosticPayload(
                state: state.rawValue,
                document: document
            )),
            as: UTF8.self
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO diagnostic_outbox(
              event_id,
              aggregate_type,
              aggregate_id,
              aggregate_revision,
              event_type,
              occurred_at,
              payload_json
            ) VALUES (?, 'runtime-operation-lease', ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(eventID()),
                .text(document.operationId),
                .int(revision),
                .text(eventType),
                .text(occurredAt),
                .text(payload),
            ]
        )
    }

    private func requiredState(_ value: String?) throws -> StoredLeaseState {
        guard let value, let state = StoredLeaseState(rawValue: value) else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "runtime_operation_lease.state",
                value: value ?? "NULL"
            )
        }
        return state
    }

    private func requiredText(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "runtime_operation_lease.\(field)",
                value: value ?? "NULL"
            )
        }
        return value
    }

    private func requiredInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value) else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "runtime_operation_lease.\(field)",
                value: value ?? "NULL"
            )
        }
        return parsed
    }

    private func optionalInt(_ value: String?, field: String) throws -> Int? {
        guard let value else {
            return nil
        }
        guard let parsed = Int(value) else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "runtime_operation_lease.\(field)",
                value: value
            )
        }
        return parsed
    }
}

private enum StoredLeaseState: String {
    case active
    case released
}

private enum StoredLease {
    case missing
    case active(revision: Int, document: RuntimeOperationLeaseDocument)
    case released(revision: Int, document: RuntimeOperationLeaseDocument)
}

private struct OperationLeaseDiagnosticPayload: Encodable {
    let state: String
    let document: RuntimeOperationLeaseDocument
}

enum SQLiteRuntimeOperationLeaseLegacyImportState: String {
    case missing
    case imported
}

struct SQLiteRuntimeOperationLeaseLegacyImportRecord {
    let state: SQLiteRuntimeOperationLeaseLegacyImportState
    let operationID: String?
}
