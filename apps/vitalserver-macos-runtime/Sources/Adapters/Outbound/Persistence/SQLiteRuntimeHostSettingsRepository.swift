import Application
import Foundation

public enum SQLiteRuntimeHostSettingsRepositoryError: Error, Equatable, CustomStringConvertible {
    case invalidStoredField(field: String, value: String)
    case lifecycleProofFailed(reason: String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidStoredField(let field, let value):
            return "Host settings SQLite field is invalid field=\(field) value=\(value)"
        case .lifecycleProofFailed(let reason):
            return "Host settings lifecycle proof failed reason=\(reason)"
        case .writeFailed(let path, let reason):
            return "Host settings SQLite write failed path=\(path) reason=\(reason)"
        }
    }
}

public struct SQLiteRuntimeHostSettingsRepository: RuntimeHostSettingsRepository, @unchecked Sendable {
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let transitionDecider: any RuntimeHostSettingsTransitionDeciding
    private let eventID: @Sendable () -> String
    private let encoder: JSONEncoder

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        transitionDecider: any RuntimeHostSettingsTransitionDeciding,
        eventID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.transitionDecider = transitionDecider
        self.eventID = eventID
        self.encoder = encoder
    }

    public func loadHostSettings() -> RuntimeHostSettingsReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let record = try loadRecord(db) else { return .missing }
                return .loaded(record)
            }
        } catch {
            return .failed("Host settings SQLite read failed path=\(databaseURL.path) reason=\(error)")
        }
    }

    public func importMaterializedHostSettings(
        _ payload: RuntimeHostSettingsPayload,
        importedAt: String
    ) throws -> RuntimeHostSettingsRecord {
        try write { db, current in
            let revision = try transitionDecider.importRevision(currentRevision: current?.revision)
            let record = RuntimeHostSettingsRecord(
                payload: try validated(payload),
                revision: revision,
                desiredAt: try required(importedAt, field: "desired_at"),
                materializedRevision: revision,
                materializedAt: importedAt
            )
            try insert(db, record: record)
            try appendEvent(db, record: record, type: "host-settings-imported")
            return record
        }
    }

    public func saveDesiredHostSettings(
        _ payload: RuntimeHostSettingsPayload,
        expectedRevision: Int,
        desiredAt: String
    ) throws -> RuntimeHostSettingsRecord {
        try write { db, current in
            let revision = try transitionDecider.nextDesiredRevision(
                currentRevision: current?.revision,
                expectedRevision: expectedRevision
            )
            guard let current else {
                throw RuntimeHostSettingsStateTransitionError.missingState
            }
            let record = RuntimeHostSettingsRecord(
                payload: try validated(payload),
                appliedPayload: current.appliedPayload,
                revision: revision,
                desiredAt: try required(desiredAt, field: "desired_at"),
                appliedRevision: current.appliedRevision,
                appliedRunID: current.appliedRunID,
                appliedAt: current.appliedAt
            )
            try update(db, record: record)
            try appendEvent(db, record: record, type: "host-settings-desired")
            return record
        }
    }

    public func markHostSettingsMaterialized(
        revision: Int,
        materializedAt: String
    ) throws -> RuntimeHostSettingsRecord {
        try write { db, current in
            guard let current else { throw RuntimeHostSettingsStateTransitionError.missingState }
            try transitionDecider.requireMaterialization(record: current, revision: revision)
            let record = copy(
                current,
                materializedRevision: revision,
                materializedAt: try required(materializedAt, field: "materialized_at")
            )
            try update(db, record: record)
            try appendEvent(db, record: record, type: "host-settings-materialized")
            return record
        }
    }

    public func recordHostSettingsBoot(
        revision: Int,
        runID: String,
        startedAt: String
    ) throws -> RuntimeHostSettingsRecord {
        try write { db, current in
            guard let current else { throw RuntimeHostSettingsStateTransitionError.missingState }
            try transitionDecider.requireBoot(record: current, revision: revision, runID: runID)
            try requireLifecycle(db, runID: runID, allowedStates: ["starting", "bootstrapping", "running"])
            let record = copy(
                current,
                bootRevision: revision,
                bootRunID: runID,
                bootStartedAt: try required(startedAt, field: "boot_started_at")
            )
            try update(db, record: record)
            try appendEvent(db, record: record, type: "host-settings-boot-started")
            return record
        }
    }

    public func markHostSettingsApplied(
        revision: Int,
        runID: String,
        appliedAt: String
    ) throws -> RuntimeHostSettingsRecord {
        try write { db, current in
            guard let current else { throw RuntimeHostSettingsStateTransitionError.missingState }
            try transitionDecider.requireApply(record: current, revision: revision, runID: runID)
            try requireLifecycle(db, runID: runID, allowedStates: ["bootstrapping", "running"])
            let record = copy(
                current,
                appliedPayload: current.payload,
                appliedRevision: revision,
                appliedRunID: runID,
                appliedAt: try required(appliedAt, field: "applied_at")
            )
            try update(db, record: record)
            try appendEvent(db, record: record, type: "host-settings-applied")
            return record
        }
    }

    private func write(
        _ operation: (OpaquePointer, RuntimeHostSettingsRecord?) throws -> RuntimeHostSettingsRecord
    ) throws -> RuntimeHostSettingsRecord {
        do {
            return try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                return try connection.withImmediateTransaction(db) {
                    try operation(db, loadRecord(db))
                }
            }
        } catch let error as RuntimeHostSettingsStateTransitionError {
            throw error
        } catch let error as SQLiteRuntimeHostSettingsRepositoryError {
            throw error
        } catch {
            throw SQLiteRuntimeHostSettingsRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func loadRecord(_ db: OpaquePointer) throws -> RuntimeHostSettingsRecord? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT revision, vm_config_json, guest_runtime_config_json,
                   guest_runtime_settings_json, desired_at, materialized_revision,
                   materialized_at, boot_revision, boot_run_id, boot_started_at,
                   applied_revision, applied_run_id, applied_at,
                   applied_vm_config_json, applied_guest_runtime_config_json,
                   applied_guest_runtime_settings_json
            FROM host_runtime_settings WHERE singleton_id = 1
            """,
            columnCount: 16
        ) else { return nil }
        let appliedRevision = try optionalPositiveInt(row[10], field: "applied_revision")
        let appliedPayload = try decodedAppliedPayload(
            revision: appliedRevision,
            vmConfig: row[13],
            guestRuntimeConfig: row[14],
            guestRuntimeSettings: row[15]
        )
        let payload = try validated(RuntimeHostSettingsPayload(
                vmConfigJSON: Data(try required(row[1], field: "vm_config_json").utf8),
                guestRuntimeConfigJSON: Data(try required(row[2], field: "guest_runtime_config_json").utf8),
                guestRuntimeSettingsJSON: Data(try required(row[3], field: "guest_runtime_settings_json").utf8)
            ))
        return RuntimeHostSettingsRecord(
            payload: payload,
            appliedPayload: appliedPayload,
            revision: try positiveInt(row[0], field: "revision"),
            desiredAt: try required(row[4], field: "desired_at"),
            materializedRevision: try optionalPositiveInt(row[5], field: "materialized_revision"),
            materializedAt: row[6],
            bootRevision: try optionalPositiveInt(row[7], field: "boot_revision"),
            bootRunID: row[8],
            bootStartedAt: row[9],
            appliedRevision: appliedRevision,
            appliedRunID: row[11],
            appliedAt: row[12]
        )
    }

    private func insert(_ db: OpaquePointer, record: RuntimeHostSettingsRecord) throws {
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO host_runtime_settings(
              singleton_id, revision, vm_config_json, guest_runtime_config_json,
              guest_runtime_settings_json, desired_at, materialized_revision,
              materialized_at, boot_revision, boot_run_id, boot_started_at,
              applied_revision, applied_run_id, applied_at, applied_vm_config_json,
              applied_guest_runtime_config_json, applied_guest_runtime_settings_json
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: try bindings(record)
        )
    }

    private func update(_ db: OpaquePointer, record: RuntimeHostSettingsRecord) throws {
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE host_runtime_settings SET
              revision = ?, vm_config_json = ?, guest_runtime_config_json = ?,
              guest_runtime_settings_json = ?, desired_at = ?, materialized_revision = ?,
              materialized_at = ?, boot_revision = ?, boot_run_id = ?, boot_started_at = ?,
              applied_revision = ?, applied_run_id = ?, applied_at = ?,
              applied_vm_config_json = ?, applied_guest_runtime_config_json = ?,
              applied_guest_runtime_settings_json = ?
            WHERE singleton_id = 1
            """,
            bindings: try bindings(record)
        )
    }

    private func bindings(_ record: RuntimeHostSettingsRecord) throws -> [SQLiteHostRuntimeStateBinding] {
        let payload = try validated(record.payload)
        let appliedPayload = try validatedAppliedPayload(
            record.appliedPayload,
            appliedRevision: record.appliedRevision
        )
        return [
            .int(record.revision),
            .text(try jsonText(payload.vmConfigJSON, field: "vm_config_json")),
            .text(try jsonText(payload.guestRuntimeConfigJSON, field: "guest_runtime_config_json")),
            .text(try jsonText(payload.guestRuntimeSettingsJSON, field: "guest_runtime_settings_json")),
            .text(try required(record.desiredAt, field: "desired_at")),
            .optionalInt(record.materializedRevision), .optionalText(record.materializedAt),
            .optionalInt(record.bootRevision), .optionalText(record.bootRunID),
            .optionalText(record.bootStartedAt), .optionalInt(record.appliedRevision),
            .optionalText(record.appliedRunID), .optionalText(record.appliedAt),
            .optionalText(try appliedPayload.map { try jsonText($0.vmConfigJSON, field: "applied_vm_config_json") }),
            .optionalText(try appliedPayload.map { try jsonText($0.guestRuntimeConfigJSON, field: "applied_guest_runtime_config_json") }),
            .optionalText(try appliedPayload.map { try jsonText($0.guestRuntimeSettingsJSON, field: "applied_guest_runtime_settings_json") }),
        ]
    }

    private func requireLifecycle(
        _ db: OpaquePointer,
        runID: String,
        allowedStates: [String]
    ) throws {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: "SELECT run_id, state FROM vm_lifecycle WHERE singleton_id = 1",
            columnCount: 2
        ), row[0] == runID, let state = row[1], allowedStates.contains(state) else {
            let allowedStateText = allowedStates.joined(separator: ",")
            throw SQLiteRuntimeHostSettingsRepositoryError.lifecycleProofFailed(
                reason: "expected runId=\(runID) states=\(allowedStateText)"
            )
        }
    }

    private func appendEvent(
        _ db: OpaquePointer,
        record: RuntimeHostSettingsRecord,
        type: String
    ) throws {
        let payload = DiagnosticPayload(
            revision: record.revision,
            materializedRevision: record.materializedRevision,
            bootRevision: record.bootRevision,
            bootRunID: record.bootRunID,
            appliedRevision: record.appliedRevision,
            appliedRunID: record.appliedRunID
        )
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw invalid(field: "diagnostic_payload", value: "not-utf8")
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO diagnostic_outbox(
              event_id, aggregate_type, aggregate_id, aggregate_revision,
              event_type, occurred_at, payload_json
            ) VALUES (?, 'host-settings', 'singleton', ?, ?, ?, ?)
            """,
            bindings: [
                .text(eventID()), .int(record.revision), .text(type),
                .text(record.appliedAt ?? record.bootStartedAt ?? record.materializedAt ?? record.desiredAt),
                .text(json),
            ]
        )
    }

    private func copy(
        _ record: RuntimeHostSettingsRecord,
        appliedPayload: RuntimeHostSettingsPayload? = nil,
        materializedRevision: Int? = nil,
        materializedAt: String? = nil,
        bootRevision: Int? = nil,
        bootRunID: String? = nil,
        bootStartedAt: String? = nil,
        appliedRevision: Int? = nil,
        appliedRunID: String? = nil,
        appliedAt: String? = nil
    ) -> RuntimeHostSettingsRecord {
        RuntimeHostSettingsRecord(
            payload: record.payload,
            appliedPayload: appliedPayload ?? record.appliedPayload,
            revision: record.revision,
            desiredAt: record.desiredAt,
            materializedRevision: materializedRevision ?? record.materializedRevision,
            materializedAt: materializedAt ?? record.materializedAt,
            bootRevision: bootRevision ?? record.bootRevision,
            bootRunID: bootRunID ?? record.bootRunID,
            bootStartedAt: bootStartedAt ?? record.bootStartedAt,
            appliedRevision: appliedRevision ?? record.appliedRevision,
            appliedRunID: appliedRunID ?? record.appliedRunID,
            appliedAt: appliedAt ?? record.appliedAt
        )
    }

    private func validated(_ payload: RuntimeHostSettingsPayload) throws -> RuntimeHostSettingsPayload {
        _ = try jsonText(payload.vmConfigJSON, field: "vm_config_json")
        _ = try jsonText(payload.guestRuntimeConfigJSON, field: "guest_runtime_config_json")
        _ = try jsonText(payload.guestRuntimeSettingsJSON, field: "guest_runtime_settings_json")
        return payload
    }

    private func validatedAppliedPayload(
        _ payload: RuntimeHostSettingsPayload?,
        appliedRevision: Int?
    ) throws -> RuntimeHostSettingsPayload? {
        switch (appliedRevision, payload) {
        case (nil, nil):
            return nil
        case (.some, .some(let payload)):
            return try validated(payload)
        case (nil, .some):
            throw invalid(field: "applied_payload", value: "present-without-applied-revision")
        case (.some, nil):
            throw invalid(field: "applied_payload", value: "missing-for-applied-revision")
        }
    }

    private func decodedAppliedPayload(
        revision: Int?,
        vmConfig: String?,
        guestRuntimeConfig: String?,
        guestRuntimeSettings: String?
    ) throws -> RuntimeHostSettingsPayload? {
        let values = [vmConfig, guestRuntimeConfig, guestRuntimeSettings]
        guard revision != nil else {
            guard values.allSatisfy({ $0 == nil }) else {
                throw invalid(field: "applied_payload", value: "present-without-applied-revision")
            }
            return nil
        }
        guard let vmConfig, let guestRuntimeConfig, let guestRuntimeSettings else {
            throw invalid(field: "applied_payload", value: "missing-for-applied-revision")
        }
        return try validated(RuntimeHostSettingsPayload(
            vmConfigJSON: Data(vmConfig.utf8),
            guestRuntimeConfigJSON: Data(guestRuntimeConfig.utf8),
            guestRuntimeSettingsJSON: Data(guestRuntimeSettings.utf8)
        ))
    }

    private func jsonText(_ data: Data, field: String) throws -> String {
        guard !data.isEmpty, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw invalid(field: field, value: "empty-or-not-utf8")
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw invalid(field: field, value: "invalid-json")
        }
        return value
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else { throw invalid(field: field, value: value ?? "NULL") }
        return value
    }

    private func positiveInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value), parsed > 0 else {
            throw invalid(field: field, value: value ?? "NULL")
        }
        return parsed
    }

    private func optionalPositiveInt(_ value: String?, field: String) throws -> Int? {
        guard value != nil else { return nil }
        return try positiveInt(value, field: field)
    }

    private func invalid(field: String, value: String) -> SQLiteRuntimeHostSettingsRepositoryError {
        .invalidStoredField(field: field, value: value)
    }
}

private struct DiagnosticPayload: Codable {
    let revision: Int
    let materializedRevision: Int?
    let bootRevision: Int?
    let bootRunID: String?
    let appliedRevision: Int?
    let appliedRunID: String?
}
