import Contracts
import Foundation

public enum InstalledProductReleaseValidationError:
    Error,
    Equatable,
    Sendable
{
    case journalIsNotSucceeded(UpdateBootstrapJournalState)
    case completionMissing
    case completionIsNotSucceeded(UpdateBootstrapCompletionOutcome)
    case invalidField(field: String, value: String)
    case invalidReleaseRevision(Int)
    case invalidEvidenceShape(InstalledProductReleaseSource)
    case productMismatch(expected: String, actual: String)
    case journalMismatch(field: String, expected: String, actual: String)
}

public enum InstalledProductReleasePolicy {
    public static func makePackageInstall(
        productId: String,
        productVersion: String,
        runtimeVersion: String,
        installOperationId: String,
        settledAt: String
    ) throws -> InstalledProductRelease {
        let release = InstalledProductRelease(
            schemaVersion: "v1",
            productId: productId,
            productVersion: productVersion,
            runtimeVersion: runtimeVersion,
            releaseRevision: 1,
            source: .packageInstall,
            installOperationId: installOperationId,
            updateId: nil,
            journalId: nil,
            journalRevision: nil,
            reportRelativePath: nil,
            reportSHA256: nil,
            settledAt: settledAt
        )
        try validate(release)
        return release
    }

    public static func makeUpdate(
        current: InstalledProductRelease,
        from journal: UpdateBootstrapJournal
    ) throws -> InstalledProductRelease {
        try validate(current)
        guard current.productId == journal.envelope.productId else {
            throw InstalledProductReleaseValidationError.productMismatch(
                expected: current.productId,
                actual: journal.envelope.productId
            )
        }
        let completion = try succeededCompletion(journal)
        let release = InstalledProductRelease(
            schemaVersion: "v1",
            productId: journal.envelope.productId,
            productVersion: journal.envelope.targetRelease.productVersion,
            runtimeVersion: journal.envelope.targetRelease.runtimeVersion,
            releaseRevision: current.releaseRevision + 1,
            source: .update,
            installOperationId: nil,
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

    public static func validate(_ release: InstalledProductRelease) throws {
        try require(release.schemaVersion == "v1", "schemaVersion", release.schemaVersion)
        try requireIdentifier(release.productId, "productId")
        try requireVersion(release.productVersion, "productVersion")
        try requireVersion(release.runtimeVersion, "runtimeVersion")
        guard release.releaseRevision > 0 else {
            throw InstalledProductReleaseValidationError.invalidReleaseRevision(
                release.releaseRevision
            )
        }
        try requireCanonicalTimestamp(release.settledAt, "settledAt")

        switch release.source {
        case .packageInstall:
            guard let operationId = release.installOperationId,
                  release.releaseRevision == 1,
                  release.updateId == nil,
                  release.journalId == nil,
                  release.journalRevision == nil,
                  release.reportRelativePath == nil,
                  release.reportSHA256 == nil else {
                throw InstalledProductReleaseValidationError.invalidEvidenceShape(
                    release.source
                )
            }
            try requireIdentifier(operationId, "installOperationId")
        case .update:
            guard release.installOperationId == nil,
                  let updateId = release.updateId,
                  let journalId = release.journalId,
                  let journalRevision = release.journalRevision,
                  let reportRelativePath = release.reportRelativePath,
                  let reportSHA256 = release.reportSHA256,
                  journalRevision > 0 else {
                throw InstalledProductReleaseValidationError.invalidEvidenceShape(
                    release.source
                )
            }
            try requireIdentifier(updateId, "updateId")
            try requireIdentifier(journalId, "journalId")
            try requireSafeRelativePath(reportRelativePath, "reportRelativePath")
            try requireSHA256(reportSHA256, "reportSHA256")
        }
    }

    public static func validate(
        _ release: InstalledProductRelease,
        against journal: UpdateBootstrapJournal
    ) throws {
        try validate(release)
        let completion = try succeededCompletion(journal)
        let expected: [String: String] = [
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
        let actual: [String: String] = [
            "productId": release.productId,
            "productVersion": release.productVersion,
            "runtimeVersion": release.runtimeVersion,
            "updateId": release.updateId ?? "",
            "journalId": release.journalId ?? "",
            "journalRevision": release.journalRevision.map(String.init) ?? "",
            "reportRelativePath": release.reportRelativePath ?? "",
            "reportSHA256": release.reportSHA256 ?? "",
            "settledAt": release.settledAt,
        ]
        for field in expected.keys.sorted() where expected[field] != actual[field] {
            throw InstalledProductReleaseValidationError.journalMismatch(
                field: field,
                expected: expected[field] ?? "",
                actual: actual[field] ?? ""
            )
        }
    }

    private static func succeededCompletion(
        _ journal: UpdateBootstrapJournal
    ) throws -> UpdateBootstrapCompletionReceipt {
        guard journal.state == .succeeded else {
            throw InstalledProductReleaseValidationError.journalIsNotSucceeded(
                journal.state
            )
        }
        guard let completion = journal.completion else {
            throw InstalledProductReleaseValidationError.completionMissing
        }
        guard completion.outcome == .succeeded else {
            throw InstalledProductReleaseValidationError.completionIsNotSucceeded(
                completion.outcome
            )
        }
        return completion
    }

    private static func requireIdentifier(_ value: String, _ field: String) throws {
        try require(
            !value.isEmpty
                && value.count <= 128
                && isAllowedASCII(value, punctuation: "-._"),
            field,
            value
        )
    }

    private static func requireVersion(_ value: String, _ field: String) throws {
        try require(
            !value.isEmpty
                && value.count <= 128
                && isAllowedASCII(value, punctuation: ".+-_"),
            field,
            value
        )
    }

    private static func requireSHA256(_ value: String, _ field: String) throws {
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
            throw InstalledProductReleaseValidationError.invalidField(
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
            throw InstalledProductReleaseValidationError.invalidField(
                field: field,
                value: value
            )
        }
    }
}
