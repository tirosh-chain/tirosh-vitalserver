import Application
import Contracts
import Errors
import Foundation

public struct SQLiteRuntimeWorkflowOperationStateRepository:
    RuntimeWorkflowOperationStateRepository,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let eventID: @Sendable () -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        eventID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.eventID = eventID
        self.encoder = encoder
        self.decoder = decoder
    }

    public func loadOperationState(
        operationID: String
    ) -> RuntimeWorkflowOperationStateReadResult {
        guard !operationID.isEmpty else {
            return .failed(invalidInput(field: "operationID", value: operationID).description)
        }
        return read {
            try loadState(
                $0,
                sql: """
                SELECT
                  operation_id,
                  operation_type,
                  phase,
                  current_step,
                  step_status,
                  message,
                  reason_codes_json,
                  started_at,
                  updated_at,
                  completed_at,
                  revision
                FROM workflow_operation_states
                WHERE operation_id = ?
                """,
                bindings: [.text(operationID)]
            )
        }
    }

    public func loadLatestOperationState(
    ) -> RuntimeWorkflowOperationStateReadResult {
        read {
            try loadState(
                $0,
                sql: """
                SELECT
                  operation_id,
                  operation_type,
                  phase,
                  current_step,
                  step_status,
                  message,
                  reason_codes_json,
                  started_at,
                  updated_at,
                  completed_at,
                  revision
                FROM workflow_operation_states
                ORDER BY updated_at DESC, rowid DESC
                LIMIT 1
                """,
                bindings: []
            )
        }
    }

    public func loadLatestOperationState(
        operation: RuntimeOperation
    ) -> RuntimeWorkflowOperationStateReadResult {
        guard isKnown(operation) else {
            return .failed(invalidInput(field: "operation", value: operation.rawValue).description)
        }
        return read {
            try loadState(
                $0,
                sql: """
                SELECT
                  operation_id,
                  operation_type,
                  phase,
                  current_step,
                  step_status,
                  message,
                  reason_codes_json,
                  started_at,
                  updated_at,
                  completed_at,
                  revision
                FROM workflow_operation_states
                WHERE operation_type = ?
                ORDER BY updated_at DESC, rowid DESC
                LIMIT 1
                """,
                bindings: [.text(operation.rawValue)]
            )
        }
    }

    @discardableResult
    public func saveOperationState(
        _ mutation: RuntimeWorkflowOperationStateMutation
    ) throws -> RuntimeWorkflowOperationState {
        try validate(mutation)
        do {
            return try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                return try connection.withImmediateTransaction(db) {
                    let existing = try loadState(
                        db,
                        sql: """
                        SELECT
                          operation_id,
                          operation_type,
                          phase,
                          current_step,
                          step_status,
                          message,
                          reason_codes_json,
                          started_at,
                          updated_at,
                          completed_at,
                          revision
                        FROM workflow_operation_states
                        WHERE operation_id = ?
                        """,
                        bindings: [.text(mutation.operationID)]
                    )
                    let state = try nextState(mutation, existing: existing)
                    try writeState(db, state: state, exists: existing != nil)
                    try appendDiagnosticEvent(
                        db,
                        state: state,
                        eventType: existing == nil
                            ? "workflow-operation-state-created"
                            : "workflow-operation-state-updated"
                    )
                    return state
                }
            }
        } catch let error as SQLiteRuntimeWorkflowOperationStateRepositoryError {
            throw error
        } catch {
            throw SQLiteRuntimeWorkflowOperationStateRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func read(
        _ operation: (OpaquePointer) throws -> RuntimeWorkflowOperationState?
    ) -> RuntimeWorkflowOperationStateReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let state = try operation(db) else {
                    return .missing
                }
                return .loaded(state)
            }
        } catch {
            return .failed(
                "workflow operation state SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    private func nextState(
        _ mutation: RuntimeWorkflowOperationStateMutation,
        existing: RuntimeWorkflowOperationState?
    ) throws -> RuntimeWorkflowOperationState {
        switch (existing, mutation.expectedRevision) {
        case (.none, .none):
            return RuntimeWorkflowOperationState(
                operationID: mutation.operationID,
                operation: mutation.operation,
                phase: mutation.phase,
                currentStep: mutation.currentStep,
                stepStatus: mutation.stepStatus,
                message: mutation.message,
                reasonCodes: mutation.reasonCodes,
                startedAt: mutation.occurredAt,
                updatedAt: mutation.occurredAt,
                completedAt: mutation.completedAt,
                revision: 1
            )
        case (.none, .some):
            throw SQLiteRuntimeWorkflowOperationStateRepositoryError.missing(
                operationID: mutation.operationID
            )
        case (.some(let state), .none):
            throw SQLiteRuntimeWorkflowOperationStateRepositoryError.alreadyExists(
                operationID: mutation.operationID,
                revision: state.revision
            )
        case (.some(let state), .some(let expectedRevision)):
            guard state.revision == expectedRevision else {
                throw SQLiteRuntimeWorkflowOperationStateRepositoryError.staleRevision(
                    operationID: mutation.operationID,
                    expected: expectedRevision,
                    actual: state.revision
                )
            }
            guard state.operation == mutation.operation else {
                throw SQLiteRuntimeWorkflowOperationStateRepositoryError.operationMismatch(
                    operationID: mutation.operationID,
                    expected: state.operation.rawValue,
                    actual: mutation.operation.rawValue
                )
            }
            return RuntimeWorkflowOperationState(
                operationID: state.operationID,
                operation: state.operation,
                phase: mutation.phase,
                currentStep: mutation.currentStep,
                stepStatus: mutation.stepStatus,
                message: mutation.message,
                reasonCodes: mutation.reasonCodes,
                startedAt: state.startedAt,
                updatedAt: mutation.occurredAt,
                completedAt: mutation.completedAt,
                revision: state.revision + 1
            )
        }
    }

    private func writeState(
        _ db: OpaquePointer,
        state: RuntimeWorkflowOperationState,
        exists: Bool
    ) throws {
        let reasonCodesJSON = try jsonString(state.reasonCodes)
        if exists {
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                UPDATE workflow_operation_states
                SET phase = ?,
                    current_step = ?,
                    step_status = ?,
                    message = ?,
                    reason_codes_json = ?,
                    updated_at = ?,
                    completed_at = ?,
                    revision = ?
                WHERE operation_id = ?
                """,
                bindings: [
                    .text(state.phase.rawValue),
                    .optionalText(state.currentStep?.rawValue),
                    .optionalText(state.stepStatus?.rawValue),
                    .text(state.message),
                    .text(reasonCodesJSON),
                    .text(state.updatedAt),
                    .optionalText(state.completedAt),
                    .int(state.revision),
                    .text(state.operationID),
                ]
            )
        } else {
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO workflow_operation_states(
                  operation_id,
                  operation_type,
                  phase,
                  current_step,
                  step_status,
                  message,
                  reason_codes_json,
                  started_at,
                  updated_at,
                  completed_at,
                  revision
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(state.operationID),
                    .text(state.operation.rawValue),
                    .text(state.phase.rawValue),
                    .optionalText(state.currentStep?.rawValue),
                    .optionalText(state.stepStatus?.rawValue),
                    .text(state.message),
                    .text(reasonCodesJSON),
                    .text(state.startedAt),
                    .text(state.updatedAt),
                    .optionalText(state.completedAt),
                    .int(state.revision),
                ]
            )
        }
    }

    private func appendDiagnosticEvent(
        _ db: OpaquePointer,
        state: RuntimeWorkflowOperationState,
        eventType: String
    ) throws {
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
            ) VALUES (?, 'workflow-operation-state', ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(eventID()),
                .text(state.operationID),
                .int(state.revision),
                .text(eventType),
                .text(state.updatedAt),
                .text(try jsonString(state)),
            ]
        )
    }

    private func loadState(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding]
    ) throws -> RuntimeWorkflowOperationState? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: sql,
            bindings: bindings,
            columnCount: 11
        ) else {
            return nil
        }
        let operation = RuntimeOperation(rawValue: try requiredText(row[1], field: "operation_type"))
        guard isKnown(operation) else {
            throw invalidInput(field: "operation_type", value: operation.rawValue)
        }
        let phase = RuntimeProgressPhase(rawValue: try requiredText(row[2], field: "phase"))
        guard isKnown(phase) else {
            throw invalidInput(field: "phase", value: phase.rawValue)
        }
        let currentStep = row[3].map(RuntimeWorkflowStep.init(rawValue:))
        if let currentStep, !isKnown(currentStep) {
            throw invalidInput(field: "current_step", value: currentStep.rawValue)
        }
        let stepStatus = row[4].map(RuntimeProgressStepStatus.init(rawValue:))
        if let stepStatus, !isKnown(stepStatus) {
            throw invalidInput(field: "step_status", value: stepStatus.rawValue)
        }
        guard (currentStep == nil) == (stepStatus == nil) else {
            throw invalidInput(field: "step_pair", value: "incomplete")
        }
        let reasonCodesText = try requiredText(row[6], field: "reason_codes_json")
        let reasonCodes: [String]
        do {
            reasonCodes = try decoder.decode([String].self, from: Data(reasonCodesText.utf8))
        } catch {
            throw invalidInput(field: "reason_codes_json", value: reasonCodesText)
        }
        let revision = try requiredInt(row[10], field: "revision")
        guard revision > 0 else {
            throw invalidInput(field: "revision", value: String(revision))
        }
        return RuntimeWorkflowOperationState(
            operationID: try requiredText(row[0], field: "operation_id"),
            operation: operation,
            phase: phase,
            currentStep: currentStep,
            stepStatus: stepStatus,
            message: try requiredText(row[5], field: "message"),
            reasonCodes: reasonCodes,
            startedAt: try requiredText(row[7], field: "started_at"),
            updatedAt: try requiredText(row[8], field: "updated_at"),
            completedAt: row[9],
            revision: revision
        )
    }

    private func validate(_ mutation: RuntimeWorkflowOperationStateMutation) throws {
        guard !mutation.operationID.isEmpty else {
            throw invalidInput(field: "operationID", value: mutation.operationID)
        }
        guard isKnown(mutation.operation) else {
            throw invalidInput(field: "operation", value: mutation.operation.rawValue)
        }
        guard isKnown(mutation.phase) else {
            throw invalidInput(field: "phase", value: mutation.phase.rawValue)
        }
        guard !mutation.message.isEmpty else {
            throw invalidInput(field: "message", value: mutation.message)
        }
        guard !mutation.occurredAt.isEmpty else {
            throw invalidInput(field: "occurredAt", value: mutation.occurredAt)
        }
        guard (mutation.currentStep == nil) == (mutation.stepStatus == nil) else {
            throw invalidInput(field: "stepPair", value: "incomplete")
        }
        if let currentStep = mutation.currentStep, !isKnown(currentStep) {
            throw invalidInput(field: "currentStep", value: currentStep.rawValue)
        }
        if let stepStatus = mutation.stepStatus, !isKnown(stepStatus) {
            throw invalidInput(field: "stepStatus", value: stepStatus.rawValue)
        }
        if let expectedRevision = mutation.expectedRevision, expectedRevision <= 0 {
            throw invalidInput(field: "expectedRevision", value: String(expectedRevision))
        }
        if let completedAt = mutation.completedAt, completedAt.isEmpty {
            throw invalidInput(field: "completedAt", value: completedAt)
        }
    }

    private func jsonString<Value: Encodable>(_ value: Value) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else {
            throw invalidInput(field: "json", value: "not-utf8")
        }
        return string
    }

    private func requiredText(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw invalidInput(field: field, value: value ?? "NULL")
        }
        return value
    }

    private func requiredInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value) else {
            throw invalidInput(field: field, value: value ?? "NULL")
        }
        return parsed
    }

    private func invalidInput(
        field: String,
        value: String
    ) -> SQLiteRuntimeWorkflowOperationStateRepositoryError {
        .invalidInput(field: field, value: value)
    }

    private func isKnown(_ value: RuntimeOperation) -> Bool {
        if case .unknown = value { return false }
        return true
    }

    private func isKnown(_ value: RuntimeProgressPhase) -> Bool {
        if case .unknown = value { return false }
        return true
    }

    private func isKnown(_ value: RuntimeWorkflowStep) -> Bool {
        if case .unknown = value { return false }
        return true
    }

    private func isKnown(_ value: RuntimeProgressStepStatus) -> Bool {
        if case .unknown = value { return false }
        return true
    }
}
