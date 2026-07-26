import Application
import Contracts
import Errors
import Foundation

public struct SQLiteRuntimeOperationLeaseLegacyMigrator:
    RuntimeOperationLeaseLegacyMigrating,
    @unchecked Sendable
{
    public static let migrationID = "runtime-operation-lease-json-v1"

    public let databaseURL: URL
    public let sourceURL: URL
    public let archiveURL: URL
    private let database: SQLiteHostRuntimeStateDatabase
    private let repository: SQLiteRuntimeOperationLeaseRepository
    private let fileStore: any RuntimeFileStore
    private let fileLock: any RuntimeFileLocking
    private let decoder: JSONDecoder
    private let timestamp: @Sendable () -> String

    public init(
        databaseURL: URL,
        sourceURL: URL,
        archiveURL: URL? = nil,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore(),
        fileLock: any RuntimeFileLocking = POSIXRuntimeFileLock(),
        decoder: JSONDecoder = JSONDecoder(),
        timestamp: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        self.databaseURL = databaseURL
        self.sourceURL = sourceURL
        self.archiveURL = archiveURL ?? sourceURL
            .deletingPathExtension()
            .appendingPathExtension("legacy-migrated.json")
        self.fileStore = fileStore
        self.fileLock = fileLock
        self.decoder = decoder
        self.timestamp = timestamp
        self.database = SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            fileStore: fileStore,
            timestamp: timestamp
        )
        self.repository = SQLiteRuntimeOperationLeaseRepository(
            databaseURL: databaseURL,
            timestamp: timestamp
        )
    }

    public func migrate() throws -> RuntimeOperationLeaseLegacyMigrationResult {
        do {
            _ = try database.initialize()
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.databaseFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }

        do {
            return try fileLock.withExclusiveLock(for: sourceURL) {
                try migrateWhileLocked()
            }
        } catch let error as RuntimeOperationLeaseLegacyMigrationError {
            throw error
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.sourceReadFailed(
                path: sourceURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func migrateWhileLocked() throws -> RuntimeOperationLeaseLegacyMigrationResult {
        let completed = try loadCompletedImport()
        if let completed {
            return try finalizeCompletedImport(completed)
        }

        let sourceState = fileStore.pathState(at: sourceURL)
        switch sourceState {
        case .missing:
            try recordMissingSource()
            return .sourceMissing
        case .file:
            try requireArchiveMissing()
            let document = try loadLegacyDocument()
            try importDocument(document)
            try archiveSource()
            return .imported(
                operationId: document.operationId,
                archivePath: archiveURL.path
            )
        case .inspectFailed(let reason):
            throw RuntimeOperationLeaseLegacyMigrationError.sourceInspectionFailed(
                path: sourceURL.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeOperationLeaseLegacyMigrationError.unexpectedSourceState(
                path: sourceURL.path,
                state: sourceState.rawValue
            )
        }
    }

    private func loadCompletedImport() throws -> SQLiteRuntimeOperationLeaseLegacyImportRecord? {
        do {
            return try repository.loadLegacyImportRecord(migrationID: Self.migrationID)
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.databaseFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func recordMissingSource() throws {
        do {
            try repository.recordMissingLegacySource(
                migrationID: Self.migrationID,
                sourcePath: sourceURL.path,
                completedAt: timestamp()
            )
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.databaseFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func importDocument(_ document: RuntimeOperationLeaseDocument) throws {
        do {
            try repository.importLegacyDocument(
                document,
                migrationID: Self.migrationID,
                sourcePath: sourceURL.path,
                completedAt: timestamp()
            )
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.databaseFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func loadLegacyDocument() throws -> RuntimeOperationLeaseDocument {
        let data: Data
        do {
            data = try fileStore.readData(sourceURL)
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.sourceReadFailed(
                path: sourceURL.path,
                reason: String(describing: error)
            )
        }
        do {
            return try decoder.decode(RuntimeOperationLeaseDocument.self, from: data)
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.sourceDecodeFailed(
                path: sourceURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func requireArchiveMissing() throws {
        switch fileStore.pathState(at: archiveURL) {
        case .missing:
            return
        case .file, .directory, .other, .unknown:
            throw RuntimeOperationLeaseLegacyMigrationError.archiveConflict(
                path: archiveURL.path
            )
        case .inspectFailed(let reason):
            throw RuntimeOperationLeaseLegacyMigrationError.sourceInspectionFailed(
                path: archiveURL.path,
                reason: reason
            )
        }
    }

    private func archiveSource() throws {
        do {
            try fileStore.moveItem(at: sourceURL, to: archiveURL)
        } catch {
            throw RuntimeOperationLeaseLegacyMigrationError.archiveFailed(
                source: sourceURL.path,
                destination: archiveURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func finalizeCompletedImport(
        _ completed: SQLiteRuntimeOperationLeaseLegacyImportRecord
    ) throws -> RuntimeOperationLeaseLegacyMigrationResult {
        let sourceState = fileStore.pathState(at: sourceURL)
        switch sourceState {
        case .missing:
            return .alreadyCompleted(
                sourceState: completed.state.rawValue,
                archivePath: try archivePathIfPresent()
            )
        case .file:
            guard completed.state == .imported else {
                throw RuntimeOperationLeaseLegacyMigrationError.sourceReappeared(
                    path: sourceURL.path,
                    completedState: completed.state.rawValue
                )
            }
            switch fileStore.pathState(at: archiveURL) {
            case .missing:
                try archiveSource()
                return .alreadyCompleted(
                    sourceState: completed.state.rawValue,
                    archivePath: archiveURL.path
                )
            case .file, .directory, .other, .unknown:
                throw RuntimeOperationLeaseLegacyMigrationError.sourceReappeared(
                    path: sourceURL.path,
                    completedState: completed.state.rawValue
                )
            case .inspectFailed(let reason):
                throw RuntimeOperationLeaseLegacyMigrationError.sourceInspectionFailed(
                    path: archiveURL.path,
                    reason: reason
                )
            }
        case .inspectFailed(let reason):
            throw RuntimeOperationLeaseLegacyMigrationError.sourceInspectionFailed(
                path: sourceURL.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeOperationLeaseLegacyMigrationError.unexpectedSourceState(
                path: sourceURL.path,
                state: sourceState.rawValue
            )
        }
    }

    private func archivePathIfPresent() throws -> String? {
        let state = fileStore.pathState(at: archiveURL)
        switch state {
        case .file:
            return archiveURL.path
        case .missing:
            return nil
        case .inspectFailed(let reason):
            throw RuntimeOperationLeaseLegacyMigrationError.sourceInspectionFailed(
                path: archiveURL.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeOperationLeaseLegacyMigrationError.unexpectedSourceState(
                path: archiveURL.path,
                state: state.rawValue
            )
        }
    }
}
