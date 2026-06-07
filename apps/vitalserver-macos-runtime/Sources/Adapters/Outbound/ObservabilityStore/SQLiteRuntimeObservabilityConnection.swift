import Contracts
import Foundation
import SQLite3
import Errors

struct SQLiteRuntimeObservabilityConnection {
    let url: URL

    func removeDatabaseFiles() throws {
        let fileManager = FileManager.default
        for path in [url.path, "\(url.path)-wal", "\(url.path)-shm"] {
            let fileURL = URL(fileURLWithPath: path)
            let state = pathState(at: fileURL, fileManager: fileManager)
            switch state {
            case .file:
                try fileManager.removeItem(atPath: path)
            case .missing:
                continue
            case .inspectFailed(let reason):
                throw SQLiteRuntimeObservabilityStoreError.pathInspectionFailed(path: path, reason: reason)
            case .directory, .other, .unknown:
                throw SQLiteRuntimeObservabilityStoreError.unexpectedPathState(
                    path: path,
                    state: state.rawValue
                )
            }
        }
    }

    func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK,
              let openedDB = db else {
            let message = db.map(sqliteErrorMessage) ?? "unknown sqlite open error"
            sqlite3_close(db)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedDB)
        }
        return try operation(openedDB)
    }

    func withReadOnlyDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK,
              let openedDB = db else {
            let message = db.map(sqliteErrorMessage) ?? "unknown sqlite open error"
            sqlite3_close(db)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedDB)
        }
        return try operation(openedDB)
    }

    private func pathState(at url: URL, fileManager: FileManager) -> RuntimePathState {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return .other("missing-file-type")
            }
            switch type {
            case .typeRegular:
                return .file
            case .typeDirectory:
                return .directory
            default:
                return .other(type.rawValue)
            }
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
    }

    private func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}
