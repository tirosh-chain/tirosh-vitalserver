import Errors
import SQLite3

enum SQLiteHostRuntimeStateBinding {
    case int(Int)
    case text(String)
    case optionalInt(Int?)
    case optionalText(String?)
}

enum SQLiteHostRuntimeStateStatement {
    static func execute(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding] = []
    ) throws {
        try withStatement(db, sql: sql, bindings: bindings) { statement in
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return
                }
                guard result == SQLITE_ROW else {
                    throw SQLiteHostRuntimeStateDatabaseError.stepFailed(errorMessage(db))
                }
            }
        }
    }

    static func scalarInt(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding] = []
    ) throws -> Int? {
        try withStatement(db, sql: sql, bindings: bindings) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw SQLiteHostRuntimeStateDatabaseError.stepFailed(errorMessage(db))
            }
            guard sqlite3_column_type(statement, 0) != SQLITE_NULL else {
                return nil
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    static func scalarString(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding] = []
    ) throws -> String? {
        try withStatement(db, sql: sql, bindings: bindings) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw SQLiteHostRuntimeStateDatabaseError.stepFailed(errorMessage(db))
            }
            return columnString(statement, index: 0)
        }
    }

    static func integerRows(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding] = []
    ) throws -> [Int] {
        try withStatement(db, sql: sql, bindings: bindings) { statement in
            var values: [Int] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return values
                }
                guard result == SQLITE_ROW else {
                    throw SQLiteHostRuntimeStateDatabaseError.stepFailed(errorMessage(db))
                }
                guard sqlite3_column_type(statement, 0) != SQLITE_NULL else {
                    throw SQLiteHostRuntimeStateDatabaseError.stepFailed(
                        "integer query returned NULL"
                    )
                }
                values.append(Int(sqlite3_column_int64(statement, 0)))
            }
        }
    }

    static func stringRow(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding] = [],
        columnCount: Int
    ) throws -> [String?]? {
        try withStatement(db, sql: sql, bindings: bindings) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw SQLiteHostRuntimeStateDatabaseError.stepFailed(errorMessage(db))
            }
            return (0..<columnCount).map { offset in
                columnString(statement, index: Int32(offset))
            }
        }
    }

    static func stringRows(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding] = [],
        columnCount: Int
    ) throws -> [[String?]] {
        try withStatement(db, sql: sql, bindings: bindings) { statement in
            var rows: [[String?]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return rows }
                guard result == SQLITE_ROW else {
                    throw SQLiteHostRuntimeStateDatabaseError.stepFailed(errorMessage(db))
                }
                rows.append((0..<columnCount).map { offset in
                    columnString(statement, index: Int32(offset))
                })
            }
        }
    }

    static func errorMessage(_ db: OpaquePointer) -> String {
        sqlite3_errmsg(db).map(String.init(cString:)) ?? "unknown sqlite error"
    }

    private static func withStatement<T>(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding],
        operation: (OpaquePointer?) throws -> T
    ) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteHostRuntimeStateDatabaseError.prepareFailed(errorMessage(db))
        }
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement, db: db)
        return try operation(statement)
    }

    private static func bind(
        _ bindings: [SQLiteHostRuntimeStateBinding],
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
                result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            case .optionalInt(let value):
                if let value {
                    result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            case .optionalText(let value):
                if let value {
                    result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            }
            guard result == SQLITE_OK else {
                throw SQLiteHostRuntimeStateDatabaseError.bindFailed(errorMessage(db))
            }
        }
    }

    private static func columnString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let rawValue = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: rawValue)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
