import Application
import Contracts
import Foundation

public enum SQLiteRuntimeEndpointStateRepositoryError: Error, Equatable, CustomStringConvertible {
    case invalidInput(field: String, value: String)
    case lifecycleMissing
    case lifecycleMismatch(expectedRunID: String, actualRunID: String)
    case lifecycleRevisionMismatch(expected: Int, actual: Int)
    case lifecycleStateUnavailable(state: String)
    case endpointMissing
    case endpointAlreadyExists(revision: Int)
    case staleRevision(expected: Int, actual: Int)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidInput(let field, let value):
            return "runtime endpoint field is invalid field=\(field) value=\(value)"
        case .lifecycleMissing:
            return "runtime endpoint cannot be written because VM lifecycle is missing"
        case .lifecycleMismatch(let expectedRunID, let actualRunID):
            return "runtime endpoint run ID does not match VM lifecycle expected=\(expectedRunID) actual=\(actualRunID)"
        case .lifecycleRevisionMismatch(let expected, let actual):
            return "runtime endpoint lifecycle revision mismatch expected=\(expected) actual=\(actual)"
        case .lifecycleStateUnavailable(let state):
            return "runtime endpoint cannot be written for VM lifecycle state=\(state)"
        case .endpointMissing:
            return "runtime endpoint state is missing"
        case .endpointAlreadyExists(let revision):
            return "runtime endpoint state already exists revision=\(revision)"
        case .staleRevision(let expected, let actual):
            return "runtime endpoint revision is stale expected=\(expected) actual=\(actual)"
        case .writeFailed(let path, let reason):
            return "runtime endpoint SQLite write failed path=\(path) reason=\(reason)"
        }
    }
}

public struct SQLiteRuntimeEndpointStateRepository:
    RuntimeEndpointStateRepository,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let eventID: @Sendable () -> String
    private let encoder: JSONEncoder

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        eventID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.eventID = eventID
        self.encoder = encoder
    }

    public func loadRuntimeEndpointState() -> RuntimeEndpointStateReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let endpoint = try loadEndpoint(db) else {
                    return .missing
                }
                guard let lifecycle = try loadLifecycleIdentity(db) else {
                    return .stale(endpoint, reason: "VM lifecycle is missing")
                }
                guard endpoint.runID == lifecycle.runID else {
                    return .stale(
                        endpoint,
                        reason: "run ID mismatch endpoint=\(endpoint.runID) lifecycle=\(lifecycle.runID)"
                    )
                }
                guard endpoint.lifecycleRevision <= lifecycle.revision else {
                    return .stale(
                        endpoint,
                        reason: "lifecycle revision is ahead endpoint=\(endpoint.lifecycleRevision) lifecycle=\(lifecycle.revision)"
                    )
                }
                guard lifecycle.state == .bootstrapping || lifecycle.state == .running else {
                    return .stale(endpoint, reason: "VM lifecycle state=\(lifecycle.state.rawValue)")
                }
                return .loaded(endpoint)
            }
        } catch {
            return .failed(
                "runtime endpoint SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    @discardableResult
    public func saveRuntimeEndpointState(
        _ mutation: RuntimeEndpointStateMutation
    ) throws -> RuntimeEndpointStateRecord {
        try validate(mutation)
        do {
            return try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                return try connection.withImmediateTransaction(db) {
                    guard let lifecycle = try loadLifecycleIdentity(db) else {
                        throw SQLiteRuntimeEndpointStateRepositoryError.lifecycleMissing
                    }
                    guard lifecycle.runID == mutation.runID else {
                        throw SQLiteRuntimeEndpointStateRepositoryError.lifecycleMismatch(
                            expectedRunID: lifecycle.runID,
                            actualRunID: mutation.runID
                        )
                    }
                    guard lifecycle.revision == mutation.lifecycleRevision else {
                        throw SQLiteRuntimeEndpointStateRepositoryError.lifecycleRevisionMismatch(
                            expected: lifecycle.revision,
                            actual: mutation.lifecycleRevision
                        )
                    }
                    guard lifecycle.state == .bootstrapping || lifecycle.state == .running else {
                        throw SQLiteRuntimeEndpointStateRepositoryError.lifecycleStateUnavailable(
                            state: lifecycle.state.rawValue
                        )
                    }

                    let current = try loadEndpoint(db)
                    let revision = try nextRevision(current: current, mutation: mutation)
                    let record = RuntimeEndpointStateRecord(
                        runID: mutation.runID,
                        lifecycleRevision: mutation.lifecycleRevision,
                        address: mutation.address.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: mutation.source,
                        observedAt: mutation.observedAt,
                        revision: revision
                    )
                    try writeEndpoint(db, record: record, exists: current != nil)
                    try appendDiagnosticEvent(db, record: record)
                    return record
                }
            }
        } catch let error as SQLiteRuntimeEndpointStateRepositoryError {
            throw error
        } catch {
            throw SQLiteRuntimeEndpointStateRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func nextRevision(
        current: RuntimeEndpointStateRecord?,
        mutation: RuntimeEndpointStateMutation
    ) throws -> Int {
        switch (current, mutation.expectedRevision) {
        case (nil, nil):
            return 1
        case (nil, .some):
            throw SQLiteRuntimeEndpointStateRepositoryError.endpointMissing
        case (.some(let current), nil):
            throw SQLiteRuntimeEndpointStateRepositoryError.endpointAlreadyExists(
                revision: current.revision
            )
        case (.some(let current), .some(let expectedRevision)):
            guard current.revision == expectedRevision else {
                throw SQLiteRuntimeEndpointStateRepositoryError.staleRevision(
                    expected: expectedRevision,
                    actual: current.revision
                )
            }
            return current.revision + 1
        }
    }

    private func loadLifecycleIdentity(_ db: OpaquePointer) throws -> LifecycleIdentity? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: "SELECT run_id, revision, state FROM vm_lifecycle WHERE singleton_id = 1",
            columnCount: 3
        ) else {
            return nil
        }
        let state = RuntimeVMLifecycleState(rawValue: try requiredText(row[2], field: "vm_lifecycle.state"))
        if case .unknown = state {
            throw invalid(field: "vm_lifecycle.state", value: state.rawValue)
        }
        return LifecycleIdentity(
            runID: try requiredText(row[0], field: "vm_lifecycle.run_id"),
            revision: try requiredInt(row[1], field: "vm_lifecycle.revision"),
            state: state
        )
    }

    private func loadEndpoint(_ db: OpaquePointer) throws -> RuntimeEndpointStateRecord? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT run_id, lifecycle_revision, address, source, observed_at, revision
            FROM runtime_endpoint
            WHERE singleton_id = 1
            """,
            columnCount: 6
        ) else {
            return nil
        }
        guard let source = RuntimeGuestAddressSource(rawValue: try requiredText(row[3], field: "source")) else {
            throw invalid(field: "source", value: row[3] ?? "NULL")
        }
        return RuntimeEndpointStateRecord(
            runID: try requiredText(row[0], field: "run_id"),
            lifecycleRevision: try requiredInt(row[1], field: "lifecycle_revision"),
            address: try requiredText(row[2], field: "address"),
            source: source,
            observedAt: try requiredText(row[4], field: "observed_at"),
            revision: try requiredInt(row[5], field: "revision")
        )
    }

    private func writeEndpoint(
        _ db: OpaquePointer,
        record: RuntimeEndpointStateRecord,
        exists: Bool
    ) throws {
        let values: [SQLiteHostRuntimeStateBinding] = [
            .int(record.revision),
            .text(record.runID),
            .int(record.lifecycleRevision),
            .text(record.address),
            .text(record.source.rawValue),
            .text(record.observedAt),
        ]
        if exists {
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                UPDATE runtime_endpoint
                SET revision = ?, run_id = ?, lifecycle_revision = ?, address = ?, source = ?, observed_at = ?
                WHERE singleton_id = 1
                """,
                bindings: values
            )
        } else {
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO runtime_endpoint(
                  singleton_id, revision, run_id, lifecycle_revision, address, source, observed_at
                ) VALUES (1, ?, ?, ?, ?, ?, ?)
                """,
                bindings: values
            )
        }
    }

    private func appendDiagnosticEvent(
        _ db: OpaquePointer,
        record: RuntimeEndpointStateRecord
    ) throws {
        let payload = try encoder.encode(record)
        guard let payloadJSON = String(data: payload, encoding: .utf8), !payloadJSON.isEmpty else {
            throw invalid(field: "payload_json", value: "not-utf8")
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO diagnostic_outbox(
              event_id, aggregate_type, aggregate_id, aggregate_revision,
              event_type, occurred_at, payload_json
            ) VALUES (?, 'runtime-endpoint', ?, ?, 'runtime-endpoint-observed', ?, ?)
            """,
            bindings: [
                .text(eventID()),
                .text(record.runID),
                .int(record.revision),
                .text(record.observedAt),
                .text(payloadJSON),
            ]
        )
    }

    private func validate(_ mutation: RuntimeEndpointStateMutation) throws {
        guard !mutation.runID.isEmpty else { throw invalid(field: "runID", value: mutation.runID) }
        guard mutation.lifecycleRevision > 0 else {
            throw invalid(field: "lifecycleRevision", value: String(mutation.lifecycleRevision))
        }
        let address = mutation.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw invalid(field: "address", value: mutation.address) }
        guard mutation.source == .platformAgent else {
            throw invalid(field: "source", value: mutation.source.rawValue)
        }
        guard !mutation.observedAt.isEmpty else {
            throw invalid(field: "observedAt", value: mutation.observedAt)
        }
        if let expectedRevision = mutation.expectedRevision, expectedRevision <= 0 {
            throw invalid(field: "expectedRevision", value: String(expectedRevision))
        }
    }

    private func requiredText(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else { throw invalid(field: field, value: value ?? "NULL") }
        return value
    }

    private func requiredInt(_ value: String?, field: String) throws -> Int {
        guard let value, let parsed = Int(value), parsed > 0 else {
            throw invalid(field: field, value: value ?? "NULL")
        }
        return parsed
    }

    private func invalid(field: String, value: String) -> SQLiteRuntimeEndpointStateRepositoryError {
        .invalidInput(field: field, value: value)
    }
}

private struct LifecycleIdentity {
    let runID: String
    let revision: Int
    let state: RuntimeVMLifecycleState
}
