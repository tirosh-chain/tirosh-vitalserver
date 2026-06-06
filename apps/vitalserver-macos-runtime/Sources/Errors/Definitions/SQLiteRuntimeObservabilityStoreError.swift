import Foundation

public enum SQLiteRuntimeObservabilityStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case decodeFailed(String)
    case missingColumn(table: String, column: String)
    case invalidColumnValue(table: String, column: String, value: String)
}
