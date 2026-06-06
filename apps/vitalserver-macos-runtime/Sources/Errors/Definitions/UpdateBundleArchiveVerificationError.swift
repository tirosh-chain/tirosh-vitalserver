import Foundation

public enum UpdateBundleArchiveVerificationError: Error, Equatable, CustomStringConvertible {
    case emptyArchive
    case unsafePath(String)
    case multipleRootDirectories
    case containsLink(String)
    case containsUnsupportedEntry(String, String)

    public var description: String {
        switch self {
        case .emptyArchive:
            return "empty update bundle archive"
        case .unsafePath(let path):
            return "unsafe update bundle archive path: \(path)"
        case .multipleRootDirectories:
            return "update bundle archive must contain a single root directory"
        case .containsLink(let archiveName):
            return "update bundle archive must not contain links: \(archiveName)"
        case .containsUnsupportedEntry(let archiveName, let entryType):
            return "update bundle archive must contain only regular files and directories: \(archiveName) entryType=\(entryType)"
        }
    }
}
