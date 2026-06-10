import Foundation
import SQLite3
import Errors

public struct SQLiteRuntimeObservabilitySnapshotter {
    public init() {}

    public func snapshot(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        for path in [destination.path, "\(destination.path)-wal", "\(destination.path)-shm"] {
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }

        var sourceDB: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let openedSource = sourceDB else {
            let message = sourceDB.map(sqliteErrorMessage) ?? "unknown sqlite source open error"
            sqlite3_close(sourceDB)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedSource)
        }

        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(
            destination.path,
            &destinationDB,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK,
              let openedDestination = destinationDB else {
            let message = destinationDB.map(sqliteErrorMessage) ?? "unknown sqlite destination open error"
            sqlite3_close(destinationDB)
            throw SQLiteRuntimeObservabilityStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(openedDestination)
        }

        guard let backup = sqlite3_backup_init(openedDestination, "main", openedSource, "main") else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(openedDestination))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(openedDestination))
        }
    }
}
