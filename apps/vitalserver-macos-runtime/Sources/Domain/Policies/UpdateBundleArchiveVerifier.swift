public enum UpdateBundleArchiveVerifier {
    public static func rootDirectory(listOutput: String) throws -> String {
        var rootName: String?
        for components in try validatedEntryComponents(listOutput: listOutput) {
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

    public static func validateArtifactArchiveEntries(
        listOutput: String,
        archiveName: String,
        requiredTopLevel: String?,
        allowedRootEntries: Set<String>?
    ) throws {
        for components in try validatedEntryComponents(listOutput: listOutput) {
            let rootEntry = components[0]
            if let requiredTopLevel, rootEntry != requiredTopLevel {
                throw UpdateBundleArchiveVerificationError.unexpectedTopLevelEntry(
                    archiveName,
                    rootEntry
                )
            }
            if let allowedRootEntries, !allowedRootEntries.contains(rootEntry) {
                throw UpdateBundleArchiveVerificationError.unexpectedRootEntry(
                    archiveName,
                    rootEntry
                )
            }
        }
    }

    public static func rejectUnsupportedEntryTypes(verboseListOutput: String, archiveName: String) throws {
        for line in verboseListOutput.split(whereSeparator: \.isNewline) {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw UpdateBundleArchiveVerificationError.containsLink(archiveName)
            }
            if entryType != "-" && entryType != "d" {
                throw UpdateBundleArchiveVerificationError.containsUnsupportedEntry(
                    archiveName,
                    String(entryType)
                )
            }
        }
    }

    private static func validatedEntryComponents(listOutput: String) throws -> [[String]] {
        let entries = listOutput.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else {
            throw UpdateBundleArchiveVerificationError.emptyArchive
        }

        return try entries.map { entry in
            guard !entry.hasPrefix("/"),
                  !entry.contains("\\"),
                  !entry.contains("\0")
            else {
                throw UpdateBundleArchiveVerificationError.unsafePath(entry)
            }
            let components = entry
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty,
                  !components.contains("."),
                  !components.contains("..")
            else {
                throw UpdateBundleArchiveVerificationError.unsafePath(entry)
            }
            return components
        }
    }
}
