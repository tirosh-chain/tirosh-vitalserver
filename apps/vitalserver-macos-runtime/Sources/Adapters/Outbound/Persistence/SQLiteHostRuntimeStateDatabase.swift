import Application
import Contracts
import Errors
import Foundation

public struct SQLiteHostRuntimeStateDatabase:
    RuntimeHostStateStoreReadinessReading,
    @unchecked Sendable
{
    public static let schemaVersion = SQLiteHostRuntimeStateSchema.supportedVersion

    public let url: URL
    private let fileStore: any RuntimeFileStore
    private let connection: SQLiteHostRuntimeStateConnection
    private let databaseID: @Sendable () -> String
    private let timestamp: @Sendable () -> String

    public init(
        url: URL,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore(),
        busyTimeoutMilliseconds: Int32 = 5_000,
        databaseID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        timestamp: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        self.url = url
        self.fileStore = fileStore
        self.connection = SQLiteHostRuntimeStateConnection(
            url: url,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.databaseID = databaseID
        self.timestamp = timestamp
    }

    @discardableResult
    public func initialize() throws -> RuntimeHostStateStoreMetadata {
        let databasePathState = fileStore.pathState(at: url)
        switch databasePathState {
        case .file, .missing:
            break
        case .inspectFailed(let reason):
            throw SQLiteHostRuntimeStateDatabaseError.pathInspectionFailed(
                path: url.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw SQLiteHostRuntimeStateDatabaseError.unexpectedPathState(
                path: url.path,
                state: databasePathState.rawValue
            )
        }

        let parent = url.deletingLastPathComponent()
        do {
            try fileStore.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw SQLiteHostRuntimeStateDatabaseError.directoryPreparationFailed(
                path: parent.path,
                reason: String(describing: error)
            )
        }

        return try connection.withWritableDatabase { db in
            _ = try SQLiteHostRuntimeStateSchema.migrate(
                db,
                connection: connection,
                databaseID: databaseID,
                timestamp: timestamp
            )
            return try SQLiteHostRuntimeStateSchema.validate(db)
        }
    }

    public func loadHostStateStoreReadiness() -> RuntimeHostStateStoreReadResult {
        let databasePathState = fileStore.pathState(at: url)
        switch databasePathState {
        case .missing:
            return .missing
        case .file:
            break
        case .inspectFailed(let reason):
            return .failed(RuntimeHostStateStoreFailure(
                stage: .pathInspection,
                message: SQLiteHostRuntimeStateDatabaseError.pathInspectionFailed(
                    path: url.path,
                    reason: reason
                ).description
            ))
        case .directory, .other, .unknown:
            return .failed(RuntimeHostStateStoreFailure(
                stage: .pathInspection,
                message: SQLiteHostRuntimeStateDatabaseError.unexpectedPathState(
                    path: url.path,
                    state: databasePathState.rawValue
                ).description
            ))
        }

        do {
            let metadata = try connection.withReadOnlyDatabase { db in
                try SQLiteHostRuntimeStateSchema.validate(db)
            }
            return .loaded(metadata)
        } catch {
            return .failed(RuntimeHostStateStoreFailure(
                stage: failureStage(error),
                message: String(describing: error)
            ))
        }
    }

    private func failureStage(_ error: Error) -> RuntimeHostStateStoreFailureStage {
        guard let databaseError = error as? SQLiteHostRuntimeStateDatabaseError else {
            return .metadataRead
        }
        switch databaseError {
        case .pathInspectionFailed, .unexpectedPathState:
            return .pathInspection
        case .directoryPreparationFailed:
            return .directoryPreparation
        case .openFailed:
            return .open
        case .configurationFailed:
            return .configuration
        case .schemaObjectMissing,
             .unsupportedSchemaVersion,
             .migrationSequenceInvalid:
            return .migration
        case .integrityCheckFailed:
            return .integrityCheck
        case .metadataMissing, .metadataInvalid:
            return .metadataRead
        case .transactionRollbackFailed:
            return .transaction
        case .prepareFailed, .bindFailed, .stepFailed:
            return .metadataRead
        }
    }
}
