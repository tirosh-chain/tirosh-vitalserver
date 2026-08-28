import Contracts

public enum UpdateBootstrapJournalValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(String)
    case invalidRevision(Int)
    case invalidIdentity(field: String, value: String)
    case bootstrapDigestMismatch(expected: String, actual: String)
    case invalidStateShape(UpdateBootstrapJournalState)
    case invalidStagedPath(field: String, value: String)
    case invalidCompletionReceipt(field: String)
    case invalidPlatformAgentSelectionCorrelation(field: String)
}

public enum UpdateBootstrapJournalPolicy {
    public static func validate(_ journal: UpdateBootstrapJournal) throws {
        guard journal.schemaVersion == "v2" else {
            throw UpdateBootstrapJournalValidationError.unsupportedSchemaVersion(
                journal.schemaVersion
            )
        }
        guard journal.journalRevision >= 1 else {
            throw UpdateBootstrapJournalValidationError.invalidRevision(
                journal.journalRevision
            )
        }
        try requireIdentity(journal.id, field: "id")
        try requireIdentity(journal.operationId, field: "operationId")
        try requireIdentity(journal.targetInstallationId, field: "targetInstallationId")
        guard journal.expectedInstallationRevision > 0 else {
            throw UpdateBootstrapJournalValidationError.invalidRevision(
                journal.expectedInstallationRevision
            )
        }
        try requireIdentity(journal.requestId, field: "requestId")
        guard journal.bootstrapSignedSHA256
                == journal.envelope.signature.signedSha256 else {
            throw UpdateBootstrapJournalValidationError.bootstrapDigestMismatch(
                expected: journal.envelope.signature.signedSha256,
                actual: journal.bootstrapSignedSHA256
            )
        }
        if let path = journal.stagedUpdaterRelativePath {
            try requireStagedPath(path, field: "stagedUpdaterRelativePath")
        }
        if let path = journal.stagedSpecificationRelativePath {
            try requireStagedPath(path, field: "stagedSpecificationRelativePath")
        }
        if let completion = journal.completion {
            try validate(completion, journal: journal)
        }
        if let correlation = journal.platformAgentSelectionCorrelation {
            try validate(correlation, journal: journal)
        }
        guard hasValidStateShape(journal) else {
            throw UpdateBootstrapJournalValidationError.invalidStateShape(
                journal.state
            )
        }
    }

    private static func hasValidStateShape(
        _ journal: UpdateBootstrapJournal
    ) -> Bool {
        let hasStagedPaths = journal.stagedUpdaterRelativePath != nil
            && journal.stagedSpecificationRelativePath != nil
        switch journal.state {
        case .admitted:
            return !hasStagedPaths
                && journal.stagedUpdaterRelativePath == nil
                && journal.stagedSpecificationRelativePath == nil
                && journal.completion == nil
                && journal.failureReason == nil
        case .handoffPending, .running:
            return hasStagedPaths
                && journal.completion == nil
                && journal.failureReason == nil
        case .succeeded:
            return hasStagedPaths
                && journal.completion?.outcome == .succeeded
                && journal.failureReason == nil
        case .failed:
            return journal.failureReason?.isEmpty == false
                && (journal.completion == nil
                    || journal.completion?.outcome == .failed)
        case .interrupted:
            return hasStagedPaths
                && journal.completion == nil
                && journal.failureReason?.isEmpty == false
        }
    }

    private static func validate(
        _ receipt: UpdateBootstrapCompletionReceipt,
        journal: UpdateBootstrapJournal
    ) throws {
        guard receipt.schemaVersion == "v1" else {
            throw UpdateBootstrapJournalValidationError
                .invalidCompletionReceipt(field: "schemaVersion")
        }
        guard receipt.updateId == journal.id,
              receipt.requestId == journal.requestId,
              receipt.bootstrapEnvelopeId == journal.envelope.id,
              receipt.updateSpecificationSHA256
                == journal.envelope.specification.sha256 else {
            throw UpdateBootstrapJournalValidationError
                .invalidCompletionReceipt(field: "correlation")
        }
        guard isSHA256(receipt.reportSHA256),
              isSafeRelativePath(receipt.reportRelativePath) else {
            throw UpdateBootstrapJournalValidationError
                .invalidCompletionReceipt(field: "report")
        }
        switch receipt.outcome {
        case .succeeded:
            guard receipt.failureReason == nil else {
                throw UpdateBootstrapJournalValidationError
                    .invalidCompletionReceipt(field: "failureReason")
            }
        case .failed:
            guard receipt.failureReason?.isEmpty == false else {
                throw UpdateBootstrapJournalValidationError
                    .invalidCompletionReceipt(field: "failureReason")
            }
        }
    }

    private static func validate(
        _ correlation: UpdateBootstrapPlatformAgentSelectionCorrelation,
        journal: UpdateBootstrapJournal
    ) throws {
        do {
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                .validateJournalCorrelation(correlation)
        } catch {
            throw UpdateBootstrapJournalValidationError
                .invalidPlatformAgentSelectionCorrelation(field: "identity")
        }
        guard correlation.updateId == journal.id else {
            throw UpdateBootstrapJournalValidationError
                .invalidPlatformAgentSelectionCorrelation(field: "updateId")
        }
        guard correlation.canonicalPayloadSHA256
            == journal.bootstrapSignedSHA256
        else {
            throw UpdateBootstrapJournalValidationError
                .invalidPlatformAgentSelectionCorrelation(
                    field: "canonicalPayloadSHA256"
                )
        }
    }

    private static func requireIdentity(
        _ value: String,
        field: String
    ) throws {
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(value) else {
            throw UpdateBootstrapJournalValidationError.invalidIdentity(
                field: field,
                value: value
            )
        }
    }

    private static func requireStagedPath(
        _ value: String,
        field: String
    ) throws {
        guard isSafeRelativePath(value) else {
            throw UpdateBootstrapJournalValidationError.invalidStagedPath(
                field: field,
                value: value
            )
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !value.hasPrefix("/")
            && !value.contains("\\")
            && !components.isEmpty
            && !components.contains(where: {
                $0.isEmpty || $0 == "." || $0 == ".."
            })
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}
