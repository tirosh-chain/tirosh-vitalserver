public enum UpdateBundleArchiveVerificationError: Error, Equatable, CustomStringConvertible {
    case emptyArchive
    case unsafePath(String)
    case multipleRootDirectories
    case containsLink(String)

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
        }
    }
}

public enum UpdateBundleArchiveVerifier {
    public static func rootDirectory(listOutput: String) throws -> String {
        let entries = listOutput.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else {
            throw UpdateBundleArchiveVerificationError.emptyArchive
        }

        var rootName: String?
        for entry in entries {
            guard !entry.hasPrefix("/"), !entry.contains("\\") else {
                throw UpdateBundleArchiveVerificationError.unsafePath(entry)
            }
            let components = entry
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty,
                  !components.contains("."),
                  !components.contains("..") else {
                throw UpdateBundleArchiveVerificationError.unsafePath(entry)
            }
            if let existingRoot = rootName {
                guard existingRoot == components[0] else {
                    throw UpdateBundleArchiveVerificationError.multipleRootDirectories
                }
            } else {
                rootName = components[0]
            }
        }

        guard let rootName else {
            throw UpdateBundleArchiveVerificationError.emptyArchive
        }
        return rootName
    }

    public static func rejectLinks(verboseListOutput: String, archiveName: String) throws {
        for line in verboseListOutput.split(whereSeparator: \.isNewline) {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw UpdateBundleArchiveVerificationError.containsLink(archiveName)
            }
        }
    }
}
