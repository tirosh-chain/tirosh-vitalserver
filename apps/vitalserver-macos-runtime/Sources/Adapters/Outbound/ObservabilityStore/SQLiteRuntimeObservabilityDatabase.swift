import SQLite3
import Errors

enum SQLiteBinding {
    case int(Int)
    case text(String)
    case optionalText(String?)
    case optionalInt(Int?)
}

func execute(
    _ db: OpaquePointer,
    sql: String,
    bindings: [SQLiteBinding] = []
) throws {
    try withStatement(db, sql: sql, bindings: bindings) { statement in
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(db))
            }
        }
    }
}

func countRows(
    _ db: OpaquePointer,
    sql: String,
    bindings: [SQLiteBinding]
) throws -> Int {
    try withStatement(db, sql: sql, bindings: bindings) { statement in
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(db))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

func scalarString(
    _ db: OpaquePointer,
    sql: String,
    bindings: [SQLiteBinding]
) throws -> String? {
    try withStatement(db, sql: sql, bindings: bindings) { statement in
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return columnText(statement, 0)
        }
        guard result == SQLITE_DONE else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(db))
        }
        return nil
    }
}

func containsRow(
    _ db: OpaquePointer,
    sql: String,
    bindings: [SQLiteBinding]
) throws -> Bool {
    try withStatement(db, sql: sql, bindings: bindings) { statement in
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        guard result == SQLITE_DONE else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(db))
        }
        return false
    }
}

func queryRows<T>(
    _ db: OpaquePointer,
    sql: String,
    bindings: [SQLiteBinding],
    map: (OpaquePointer?) throws -> T?
) throws -> [T] {
    try withStatement(db, sql: sql, bindings: bindings) { statement in
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }
            guard result == SQLITE_ROW else {
                throw SQLiteRuntimeObservabilityStoreError.stepFailed(sqliteErrorMessage(db))
            }
            if let row = try map(statement) {
                rows.append(row)
            }
        }
    }
}

func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let rawValue = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: rawValue)
}

func columnOptionalBool(_ statement: OpaquePointer?, _ index: Int32) -> Bool? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }
    return sqlite3_column_int64(statement, index) != 0
}

func sqliteErrorMessage(_ db: OpaquePointer) -> String {
    sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown sqlite error"
}

private func withStatement<T>(
    _ db: OpaquePointer,
    sql: String,
    bindings: [SQLiteBinding],
    operation: (OpaquePointer?) throws -> T
) throws -> T {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw SQLiteRuntimeObservabilityStoreError.prepareFailed(sqliteErrorMessage(db))
    }
    defer {
        sqlite3_finalize(statement)
    }

    try bind(bindings, to: statement, db: db)
    return try operation(statement)
}

private func bind(
    _ bindings: [SQLiteBinding],
    to statement: OpaquePointer?,
    db: OpaquePointer
) throws {
    for (offset, binding) in bindings.enumerated() {
        let index = Int32(offset + 1)
        let result: Int32
        switch binding {
        case .int(let value):
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case .text(let value):
            result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case .optionalText(let value):
            if let value {
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            } else {
                result = sqlite3_bind_null(statement, index)
            }
        case .optionalInt(let value):
            if let value {
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            } else {
                result = sqlite3_bind_null(statement, index)
            }
        }
        guard result == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.bindFailed(sqliteErrorMessage(db))
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
