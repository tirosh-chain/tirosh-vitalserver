import Contracts

public enum UpdateBootstrapBundleClosureError: Error, Equatable, Sendable {
    case invalidEntryPath(String)
    case duplicateEntry(String)
    case unsupportedEntry(path: String, kind: String)
    case duplicateArtifactPath(String)
    case fileClosureMismatch(missing: [String], unknown: [String])
}

public enum UpdateBootstrapBundleClosurePolicy {
    public static func validate(
        envelope: UpdateBootstrapEnvelope,
        entries: [UpdateBootstrapBundleEntry]
    ) throws {
        let artifactPaths = [
            envelope.nextUpdaterArtifact.relativePath,
            envelope.specification.relativePath,
        ]
        guard Set(artifactPaths).count == artifactPaths.count else {
            throw UpdateBootstrapBundleClosureError.duplicateArtifactPath(
                artifactPaths[0]
            )
        }
        let expectedFiles = Set(
            [UpdateBootstrapBundleLayout.envelopeRelativePath] + artifactPaths
        )

        var observedFiles = Set<String>()
        var observedEntries = Set<String>()
        for entry in entries {
            try requireSafeRelativePath(entry.relativePath)
            guard observedEntries.insert(entry.relativePath).inserted else {
                throw UpdateBootstrapBundleClosureError.duplicateEntry(
                    entry.relativePath
                )
            }
            switch entry.kind {
            case .regularFile:
                observedFiles.insert(entry.relativePath)
            case .directory:
                break
            case .other(let kind):
                throw UpdateBootstrapBundleClosureError.unsupportedEntry(
                    path: entry.relativePath,
                    kind: kind
                )
            }
        }

        let missing = expectedFiles.subtracting(observedFiles).sorted()
        let unknown = observedFiles.subtracting(expectedFiles).sorted()
        guard missing.isEmpty, unknown.isEmpty else {
            throw UpdateBootstrapBundleClosureError.fileClosureMismatch(
                missing: missing,
                unknown: unknown
            )
        }
    }

    private static func requireSafeRelativePath(_ value: String) throws {
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !components.contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }) else {
            throw UpdateBootstrapBundleClosureError.invalidEntryPath(value)
        }
    }
}
