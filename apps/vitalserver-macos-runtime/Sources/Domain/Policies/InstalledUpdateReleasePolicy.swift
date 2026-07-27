import Contracts
import Foundation

public enum InstalledUpdateReleaseValidationError:
    Error,
    Equatable,
    Sendable
{
    case journalIsNotSucceeded(UpdateBootstrapJournalState)
    case completionMissing
    case completionIsNotSucceeded(UpdateBootstrapCompletionOutcome)
    case invalidField(field: String, value: String)
    case invalidJournalRevision(Int)
    case journalMismatch(field: String, expected: String, actual: String)
}

public enum InstalledUpdateReleasePolicy {
    public static func make(
        from journal: UpdateBootstrapJournal
    ) throws -> InstalledUpdateRelease {
        guard journal.state == .succeeded else {
            throw InstalledUpdateReleaseValidationError.journalIsNotSucceeded(
                journal.state
            )
        }
        guard let completion = journal.completion else {
            throw InstalledUpdateReleaseValidationError.completionMissing
        }
        guard completion.outcome == .succeeded else {
            throw InstalledUpdateReleaseValidationError.completionIsNotSucceeded(
                completion.outcome
            )
        }
        let release = InstalledUpdateRelease(
            schemaVersion: "v1",
            productId: journal.envelope.productId,
            productVersion: journal.envelope.targetRelease.productVersion,
            runtimeVersion: journal.envelope.targetRelease.runtimeVersion,
            updateId: journal.id,
            journalId: journal.id,
            journalRevision: journal.journalRevision,
            reportRelativePath: completion.reportRelativePath,
            reportSHA256: completion.reportSHA256,
            settledAt: completion.finishedAt
        )
        try validate(release, against: journal)
        return release
    }

    public static func validate(_ release: InstalledUpdateRelease) throws {
        try require(
            release.schemaVersion == "v1",
            "schemaVersion",
            release.schemaVersion
        )
        try requireIdentifier(release.productId, "productId")
        try requireVersion(release.productVersion, "productVersion")
        try requireVersion(release.runtimeVersion, "runtimeVersion")
        try requireIdentifier(release.updateId, "updateId")
        try requireIdentifier(release.journalId, "journalId")
        guard release.journalRevision > 0 else {
            throw InstalledUpdateReleaseValidationError.invalidJournalRevision(
                release.journalRevision
            )
        }
        try requireSafeRelativePath(
            release.reportRelativePath,
            "reportRelativePath"
        )
        try requireSHA256(release.reportSHA256, "reportSHA256")
        try requireCanonicalTimestamp(release.settledAt, "settledAt")
    }

    public static func validate(
        _ release: InstalledUpdateRelease,
        against journal: UpdateBootstrapJournal
    ) throws {
        try validate(release)
        let expected = try makeComparableFields(journal)
        let actual = comparableFields(release)
        for field in expected.keys.sorted() {
            guard expected[field] == actual[field] else {
                throw InstalledUpdateReleaseValidationError.journalMismatch(
                    field: field,
                    expected: expected[field] ?? "",
                    actual: actual[field] ?? ""
                )
            }
        }
    }

    private static func makeComparableFields(
        _ journal: UpdateBootstrapJournal
    ) throws -> [String: String] {
        guard journal.state == .succeeded else {
            throw InstalledUpdateReleaseValidationError.journalIsNotSucceeded(
                journal.state
            )
        }
        guard let completion = journal.completion else {
            throw InstalledUpdateReleaseValidationError.completionMissing
        }
        guard completion.outcome == .succeeded else {
            throw InstalledUpdateReleaseValidationError.completionIsNotSucceeded(
                completion.outcome
            )
        }
        return [
            "productId": journal.envelope.productId,
            "productVersion": journal.envelope.targetRelease.productVersion,
            "runtimeVersion": journal.envelope.targetRelease.runtimeVersion,
            "updateId": journal.id,
            "journalId": journal.id,
            "journalRevision": String(journal.journalRevision),
            "reportRelativePath": completion.reportRelativePath,
            "reportSHA256": completion.reportSHA256,
            "settledAt": completion.finishedAt,
        ]
    }

    private static func comparableFields(
        _ release: InstalledUpdateRelease
    ) -> [String: String] {
        [
            "productId": release.productId,
            "productVersion": release.productVersion,
            "runtimeVersion": release.runtimeVersion,
            "updateId": release.updateId,
            "journalId": release.journalId,
            "journalRevision": String(release.journalRevision),
            "reportRelativePath": release.reportRelativePath,
            "reportSHA256": release.reportSHA256,
            "settledAt": release.settledAt,
        ]
    }

    private static func requireIdentifier(
        _ value: String,
        _ field: String
    ) throws {
        try require(
            !value.isEmpty
                && value.count <= 128
                && isAllowedASCII(value, punctuation: "-._"),
            field,
            value
        )
    }

    private static func requireVersion(
        _ value: String,
        _ field: String
    ) throws {
        try require(
            !value.isEmpty
                && value.count <= 128
                && isAllowedASCII(value, punctuation: ".+-_"),
            field,
            value
        )
    }

    private static func requireSHA256(
        _ value: String,
        _ field: String
    ) throws {
        try require(
            value.count == 64
                && value.allSatisfy {
                    $0.isNumber || ("a"..."f").contains(String($0))
                },
            field,
            value
        )
    }

    private static func requireSafeRelativePath(
        _ value: String,
        _ field: String
    ) throws {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        try require(
            !value.isEmpty
                && !value.hasPrefix("/")
                && !value.contains("\\")
                && !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
            field,
            value
        )
    }

    private static func requireCanonicalTimestamp(
        _ value: String,
        _ field: String
    ) throws {
        guard value.count == 20 else {
            throw InstalledUpdateReleaseValidationError.invalidField(
                field: field,
                value: value
            )
        }
        let separators: [(Int, Character)] = [
            (4, "-"),
            (7, "-"),
            (10, "T"),
            (13, ":"),
            (16, ":"),
        ]
        let hasCanonicalSeparators = separators.allSatisfy { offset, expected in
            value[value.index(value.startIndex, offsetBy: offset)] == expected
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        try require(
            hasCanonicalSeparators
                && value.hasSuffix("Z")
                && formatter.date(from: value) != nil,
            field,
            value
        )
    }

    private static func isAllowedASCII(
        _ value: String,
        punctuation: String
    ) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            return (65...90).contains(code)
                || (97...122).contains(code)
                || (48...57).contains(code)
                || punctuation.unicodeScalars.contains(scalar)
        }
    }

    private static func require(
        _ condition: Bool,
        _ field: String,
        _ value: String
    ) throws {
        guard condition else {
            throw InstalledUpdateReleaseValidationError.invalidField(
                field: field,
                value: value
            )
        }
    }
}
