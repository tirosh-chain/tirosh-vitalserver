import Errors
import Foundation
import SQLite3

struct SQLiteHostRuntimeStateConnection: Sendable {
    let url: URL
    let busyTimeoutMilliseconds: Int32

    func withWritableDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try withDatabase(
            flags: SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            configure: configureWritableDatabase,
            operation: operation
        )
    }

    func withReadOnlyDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try withDatabase(
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            configure: configureReadOnlyDatabase,
            operation: operation
        )
    }

    func withImmediateTransaction<T>(
        _ db: OpaquePointer,
        operation: () throws -> T
    ) throws -> T {
        try SQLiteHostRuntimeStateStatement.execute(db, sql: "BEGIN IMMEDIATE TRANSACTION")
        do {
            let value = try operation()
            try SQLiteHostRuntimeStateStatement.execute(db, sql: "COMMIT")
            return value
        } catch {
            do {
                try SQLiteHostRuntimeStateStatement.execute(db, sql: "ROLLBACK")
            } catch let rollbackError {
                throw SQLiteHostRuntimeStateDatabaseError.transactionRollbackFailed(
                    original: String(describing: error),
                    rollback: String(describing: rollbackError)
                )
            }
            throw error
        }
    }

    func withDeferredReadTransaction<T>(
        _ db: OpaquePointer,
        operation: () throws -> T
    ) throws -> T {
        try SQLiteHostRuntimeStateStatement.execute(db, sql: "BEGIN DEFERRED TRANSACTION")
        do {
            let value = try operation()
            try SQLiteHostRuntimeStateStatement.execute(db, sql: "COMMIT")
            return value
        } catch {
            do {
                try SQLiteHostRuntimeStateStatement.execute(db, sql: "ROLLBACK")
            } catch let rollbackError {
                throw SQLiteHostRuntimeStateDatabaseError.transactionRollbackFailed(
                    original: String(describing: error),
                    rollback: String(describing: rollbackError)
                )
            }
            throw error
        }
    }

    private func withDatabase<T>(
        flags: Int32,
        configure: (OpaquePointer) throws -> Void,
        operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, flags, nil)
        guard openResult == SQLITE_OK, let openedDatabase = database else {
            let reason = database.map(SQLiteHostRuntimeStateStatement.errorMessage)
                ?? "sqlite open returned code=\(openResult)"
            sqlite3_close(database)
            throw SQLiteHostRuntimeStateDatabaseError.openFailed(path: url.path, reason: reason)
        }
        defer {
            sqlite3_close(openedDatabase)
        }

        guard sqlite3_extended_result_codes(openedDatabase, 1) == SQLITE_OK else {
            throw SQLiteHostRuntimeStateDatabaseError.configurationFailed(
                SQLiteHostRuntimeStateStatement.errorMessage(openedDatabase)
            )
        }
        guard sqlite3_busy_timeout(openedDatabase, busyTimeoutMilliseconds) == SQLITE_OK else {
            throw SQLiteHostRuntimeStateDatabaseError.configurationFailed(
                SQLiteHostRuntimeStateStatement.errorMessage(openedDatabase)
            )
        }
        try configure(openedDatabase)
        return try operation(openedDatabase)
    }

    private func configureWritableDatabase(_ db: OpaquePointer) throws {
        let journalMode = try SQLiteHostRuntimeStateStatement.scalarString(
            db,
            sql: "PRAGMA journal_mode=WAL"
        )?.lowercased()
        guard journalMode == "wal" else {
            throw SQLiteHostRuntimeStateDatabaseError.configurationFailed(
                "journal_mode expected=wal actual=\(journalMode ?? "missing")"
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(db, sql: "PRAGMA synchronous=FULL")
        try configureCommonDatabase(db)
    }

    private func configureReadOnlyDatabase(_ db: OpaquePointer) throws {
        try configureCommonDatabase(db)
    }

    private func configureCommonDatabase(_ db: OpaquePointer) throws {
        try SQLiteHostRuntimeStateStatement.execute(db, sql: "PRAGMA foreign_keys=ON")
        let foreignKeys = try SQLiteHostRuntimeStateStatement.scalarInt(
            db,
            sql: "PRAGMA foreign_keys"
        )
        guard foreignKeys == 1 else {
            throw SQLiteHostRuntimeStateDatabaseError.configurationFailed(
                "foreign_keys expected=1 actual=\(foreignKeys.map(String.init) ?? "missing")"
            )
        }
    }
}
