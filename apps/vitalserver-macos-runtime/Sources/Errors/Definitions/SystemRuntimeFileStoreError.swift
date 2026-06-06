import Foundation

public enum SystemRuntimeFileStoreError: Error, Equatable, Sendable {
    case missingFileSize(path: String)
    case missingModificationDate(path: String)
    case missingDirectoryFlag(path: String)
    case missingRegularFileFlag(path: String)
    case missingFileSystemFreeSize(path: String)
}
