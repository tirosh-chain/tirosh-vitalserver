import Contracts

public enum UpdateBootstrapBundleClosureError: Error, Equatable, Sendable {
    case invalidEntryPath(String)
    case duplicateEntry(String)
    case unsupportedEntry(path: String, kind: String)
    case duplicateArtifactPath(String)
    case fileClosureMismatch(missing: [String], unknown: [String])
}

public enum UpdateBootstrapBundleClosurePolicy {
    public static func validateStructure(
        envelope: UpdateBootstrapEnvelope,
        entries: [UpdateBootstrapBundleEntry]
    ) throws {
        let bootstrapArtifactPaths = [
            envelope.nextUpdaterArtifact.relativePath,
            envelope.specification.relativePath,
        ] + envelope.payloadArtifacts.map(\.relativePath)
        guard Set(bootstrapArtifactPaths).count
                == bootstrapArtifactPaths.count else {
            throw UpdateBootstrapBundleClosureError.duplicateArtifactPath(
                bootstrapArtifactPaths[0]
            )
        }
        let requiredFiles = Set(
            [UpdateBootstrapBundleLayout.envelopeRelativePath]
                + bootstrapArtifactPaths
        )
        for path in requiredFiles {
            try requireSafeRelativePath(path)
        }
        let observedFiles = try inspect(entries)
        let missing = requiredFiles.subtracting(observedFiles).sorted()
        guard missing.isEmpty else {
            throw UpdateBootstrapBundleClosureError.fileClosureMismatch(
                missing: missing,
                unknown: []
            )
        }
    }

    public static func validateExact(
        envelope: UpdateBootstrapEnvelope,
        entries: [UpdateBootstrapBundleEntry]
    ) throws {
        try validateStructure(envelope: envelope, entries: entries)
        let artifactPaths = [
            envelope.nextUpdaterArtifact.relativePath,
            envelope.specification.relativePath,
        ] + envelope.payloadArtifacts.map(\.relativePath)
        var uniqueArtifactPaths = Set<String>()
        for path in artifactPaths {
            try requireSafeRelativePath(path)
            guard uniqueArtifactPaths.insert(path).inserted else {
                throw UpdateBootstrapBundleClosureError
                    .duplicateArtifactPath(path)
            }
        }
        let expectedFiles = Set(
            [UpdateBootstrapBundleLayout.envelopeRelativePath]
                + artifactPaths
        )
        let observedFiles = try inspect(entries)
        let missing = expectedFiles.subtracting(observedFiles).sorted()
        let unknown = observedFiles.subtracting(expectedFiles).sorted()
        guard missing.isEmpty, unknown.isEmpty else {
            throw UpdateBootstrapBundleClosureError.fileClosureMismatch(
                missing: missing,
                unknown: unknown
            )
        }
    }

    private static func inspect(
        _ entries: [UpdateBootstrapBundleEntry]
    ) throws -> Set<String> {
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
        return observedFiles
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
