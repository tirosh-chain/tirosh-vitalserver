import Foundation

public enum SystemRuntimeFileStoreError: Error, Equatable, Sendable {
    case missingFileSize(path: String)
    case missingDirectoryFlag(path: String)
    case missingRegularFileFlag(path: String)
}
