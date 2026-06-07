import Domain

public struct ValidateUpdateBundleArchiveUseCase {
    public init() {}

    public func rootDirectory(listOutput: String) throws -> String {
        try UpdateBundleArchiveVerifier.rootDirectory(listOutput: listOutput)
    }

    public func rejectUnsupportedEntryTypes(
        verboseListOutput: String,
        archiveName: String
    ) throws {
        try UpdateBundleArchiveVerifier.rejectUnsupportedEntryTypes(
            verboseListOutput: verboseListOutput,
            archiveName: archiveName
        )
    }

    public func validateArtifactArchiveEntries(
        listOutput: String,
        archiveName: String,
        requiredTopLevel: String? = nil,
        allowedRootEntries: Set<String>? = nil
    ) throws {
        try UpdateBundleArchiveVerifier.validateArtifactArchiveEntries(
            listOutput: listOutput,
            archiveName: archiveName,
            requiredTopLevel: requiredTopLevel,
            allowedRootEntries: allowedRootEntries
        )
    }

    public func artifactArchiveValidationFailureMessage(
        _ error: Error,
        archiveName: String
    ) -> String {
        guard let archiveError = error as? UpdateBundleArchiveVerificationError else {
            return String(describing: error)
        }
        switch archiveError {
        case .emptyArchive:
            return "empty tar.gz: \(archiveName)"
        case .unsafePath(let path):
            if path.split(separator: "/", omittingEmptySubsequences: true).contains("..") {
                return "path traversal in \(archiveName): \(path)"
            }
            return "unsafe tar entry in \(archiveName): \(path)"
        case .unexpectedTopLevelEntry(_, let entry):
            return "unexpected top-level entry in \(archiveName): \(entry)"
        case .unexpectedRootEntry(_, let entry):
            return "unexpected root entry in \(archiveName): \(entry)"
        case .containsLink:
            return "tar.gz must not contain links: \(archiveName)"
        case .containsUnsupportedEntry(_, let entryType):
            return "tar.gz must contain only regular files and directories: \(archiveName) entryType=\(entryType)"
        case .multipleRootDirectories:
            return archiveError.description
        }
    }
}
