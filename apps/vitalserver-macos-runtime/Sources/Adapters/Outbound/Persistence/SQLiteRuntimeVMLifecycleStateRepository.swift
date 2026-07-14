import Application
import Contracts
import Foundation

public enum SQLiteRuntimeVMLifecycleStateRepositoryError: Error, Equatable, CustomStringConvertible {
    case invalidStoredField(field: String, value: String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidStoredField(let field, let value):
            return "VM lifecycle SQLite field is invalid field=\(field) value=\(value)"
        case .writeFailed(let path, let reason):
            return "VM lifecycle SQLite write failed path=\(path) reason=\(reason)"
        }
    }
}

public struct SQLiteRuntimeVMLifecycleStateRepository:
    RuntimeVMLifecycleStateRepository,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let eventID: @Sendable () -> String
    private let encoder: JSONEncoder
    private let transitionDecider: any RuntimeVMLifecycleTransitionDeciding

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        eventID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        encoder: JSONEncoder = JSONEncoder(),
        transitionDecider: any RuntimeVMLifecycleTransitionDeciding
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.eventID = eventID
        self.encoder = encoder
        self.transitionDecider = transitionDecider
    }

    public func loadVMLifecycleState() -> RuntimeVMLifecycleStateReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let record = try loadRecord(db) else {
                    return .missing
                }
                return .loaded(record)
            }
        } catch {
            return .failed(
                "VM lifecycle SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    @discardableResult
    public func saveVMLifecycleState(
        _ mutation: RuntimeVMLifecycleStateMutation
    ) throws -> RuntimeVMLifecycleStateRecord {
        do {
            return try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                return try connection.withImmediateTransaction(db) {
                    let current = try loadRecord(db)
                    let revision = try transitionDecider.nextRevision(
                        current: current?.document,
                        currentRevision: current?.revision,
                        proposed: mutation.document,
                        expectedRevision: mutation.expectedRevision
                    )
                    let record = RuntimeVMLifecycleStateRecord(
                        document: mutation.document,
                        revision: revision
                    )
                    try writeRecord(db, record: record, exists: current != nil)
                    try appendDiagnosticEvent(
                        db,
                        record: record,
                        eventType: mutation.document.state == .starting
                            ? "vm-lifecycle-run-started"
                            : "vm-lifecycle-transitioned"
                    )
                    return record
                }
            }
        } catch let error as RuntimeVMLifecycleStateTransitionError {
            throw error
        } catch let error as SQLiteRuntimeVMLifecycleStateRepositoryError {
            throw error
        } catch {
            throw SQLiteRuntimeVMLifecycleStateRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func loadRecord(_ db: OpaquePointer) throws -> RuntimeVMLifecycleStateRecord? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT
              revision,
              document_schema_version,
              run_id,
              state,
              operation,
              operation_id,
              started_at,
              updated_at,
              deadline_at,
              terminal_reason,
              message
            FROM vm_lifecycle
            WHERE singleton_id = 1
            """,
            columnCount: 11
        ) else {
            return nil
        }

        let revision = try requiredInt(row[0], field: "revision")
        let schemaVersion = try requiredInt(row[1], field: "document_schema_version")
        let state = RuntimeVMLifecycleState(rawValue: try requiredText(row[3], field: "state"))
        if case .unknown = state {
            throw invalid(field: "state", value: state.rawValue)
        }
        let operation = RuntimeOperation(rawValue: try requiredText(row[4], field: "operation"))
        if case .unknown = operation {
            throw invalid(field: "operation", value: operation.rawValue)
        }
        let terminalReason = row[9].map(RuntimeVMLifecycleTerminalReason.init(rawValue:))
        if let terminalReason, case .unknown = terminalReason {
            throw invalid(field: "terminal_reason", value: terminalReason.rawValue)
        }

        let document = RuntimeVMLifecycleDocument(
            schemaVersion: schemaVersion,
            state: state,
            operation: operation,
            operationID: try requiredText(row[5], field: "operation_id"),
            bootID: try requiredText(row[2], field: "run_id"),
            startedAt: try requiredText(row[6], field: "started_at"),
            updatedAt: try requiredText(row[7], field: "updated_at"),
            deadlineAt: row[8],
            terminalReason: terminalReason,
            message: row[10]
        )
        return RuntimeVMLifecycleStateRecord(document: document, revision: revision)
    }

    private func writeRecord(
        _ db: OpaquePointer,
        record: RuntimeVMLifecycleStateRecord,
        exists: Bool
    ) throws {
        let recordBindings = try bindings(record)
        if exists {
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                UPDATE vm_lifecycle
                SET revision = ?,
                    document_schema_version = ?,
                    run_id = ?,
                    state = ?,
                    operation = ?,
                    operation_id = ?,
                    started_at = ?,
                    updated_at = ?,
                    deadline_at = ?,
                    terminal_reason = ?,
                    message = ?
                WHERE singleton_id = 1
                """,
                bindings: recordBindings
            )
        } else {
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO vm_lifecycle(
                  singleton_id,
                  revision,
                  document_schema_version,
                  run_id,
                  state,
                  operation,
                  operation_id,
                  started_at,
                  updated_at,
                  deadline_at,
                  terminal_reason,
                  message
                ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: recordBindings
            )
        }
    }

    private func bindings(
        _ record: RuntimeVMLifecycleStateRecord
    ) throws -> [SQLiteHostRuntimeStateBinding] {
        let document = record.document
        return [
            .int(record.revision),
            .int(document.schemaVersion),
            .text(try requiredText(document.bootID, field: "run_id")),
            .text(document.state.rawValue),
            .text(try requiredOperation(document.operation).rawValue),
            .text(try requiredText(document.operationID, field: "operation_id")),
            .text(document.startedAt),
            .text(document.updatedAt),
            .optionalText(document.deadlineAt),
            .optionalText(document.terminalReason?.rawValue),
            .optionalText(document.message),
        ]
    }

    private func appendDiagnosticEvent(
        _ db: OpaquePointer,
        record: RuntimeVMLifecycleStateRecord,
        eventType: String
    ) throws {
        let runID = try requiredText(record.document.bootID, field: "run_id")
        let payload = try encoder.encode(record.document)
        guard let payloadJSON = String(data: payload, encoding: .utf8), !payloadJSON.isEmpty else {
            throw invalid(field: "payload_json", value: "not-utf8")
        }
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
            ) VALUES (?, 'vm-lifecycle', ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(eventID()),
                .text(runID),
                .int(record.revision),
                .text(eventType),
                .text(record.document.updatedAt),
                .text(payloadJSON),
            ]
        )
    }

    private func requiredText(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw invalid(field: field, value: value ?? "NULL")
        }
        return value
    }

    private func requiredInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value), parsed > 0 else {
            throw invalid(field: field, value: value ?? "NULL")
        }
        return parsed
    }

    private func requiredOperation(_ value: RuntimeOperation?) throws -> RuntimeOperation {
        guard let value else {
            throw invalid(field: "operation", value: "NULL")
        }
        return value
    }

    private func invalid(field: String, value: String) -> SQLiteRuntimeVMLifecycleStateRepositoryError {
        .invalidStoredField(field: field, value: value)
    }
}
