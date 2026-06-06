import Foundation

public enum JSONLRuntimeEventRepositoryError: Error, Equatable, Sendable {
    case missingFileSize(path: String)
}
