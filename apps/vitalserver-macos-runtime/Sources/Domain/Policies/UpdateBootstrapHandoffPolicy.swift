import Contracts

public enum UpdateBootstrapHandoffPolicyError: Error, Equatable, Sendable {
    case journalIsNotRunning(UpdateBootstrapJournalState)
    case missingStagedUpdaterPath
    case missingStagedSpecificationPath
    case stagedUpdaterPathMismatch(expected: String, actual: String)
    case stagedSpecificationPathMismatch(expected: String, actual: String)
    case invalidGuestControlBaseURL(String)
}

public enum UpdateBootstrapHandoffPolicy {
    public static let schemaVersion = "vitalserver.update-bootstrap-handoff/v2"
    public static let completionReceiptRelativePath =
        "handoff/completion-receipt.json"

    public static func makeInvocation(
        journal: UpdateBootstrapJournal,
        guestControlBaseURL: String
    ) throws -> UpdateBootstrapHandoffInvocation {
        try UpdateBootstrapJournalPolicy.validate(journal)
        guard journal.state == .running else {
            throw UpdateBootstrapHandoffPolicyError.journalIsNotRunning(
                journal.state
            )
        }
        guard let updaterPath = journal.stagedUpdaterRelativePath else {
            throw UpdateBootstrapHandoffPolicyError.missingStagedUpdaterPath
        }
        guard let specificationPath = journal.stagedSpecificationRelativePath else {
            throw UpdateBootstrapHandoffPolicyError.missingStagedSpecificationPath
        }
        guard updaterPath == journal.envelope.nextUpdaterArtifact.relativePath else {
            throw UpdateBootstrapHandoffPolicyError.stagedUpdaterPathMismatch(
                expected: journal.envelope.nextUpdaterArtifact.relativePath,
                actual: updaterPath
            )
        }
        guard specificationPath == journal.envelope.specification.relativePath else {
            throw UpdateBootstrapHandoffPolicyError
                .stagedSpecificationPathMismatch(
                    expected: journal.envelope.specification.relativePath,
                    actual: specificationPath
                )
        }
        guard RuntimeGuestControlEndpointPolicy
                .isAcceptableGuestControlBaseURL(guestControlBaseURL) else {
            throw UpdateBootstrapHandoffPolicyError.invalidGuestControlBaseURL(
                guestControlBaseURL
            )
        }
        return UpdateBootstrapHandoffInvocation(
            schemaVersion: schemaVersion,
            updateId: journal.id,
            operationId: journal.operationId,
            requestId: journal.requestId,
            bootstrapEnvelopeId: journal.envelope.id,
            bootstrapSignedSHA256: journal.bootstrapSignedSHA256,
            updateSpecificationSHA256: journal.envelope.specification.sha256,
            guestControlBaseURL: guestControlBaseURL,
            layerOrder: journal.envelope.layerOrder,
            payloadArtifacts: journal.envelope.payloadArtifacts,
            expectedJournalRevision: journal.journalRevision,
            updaterRelativePath: updaterPath,
            specificationRelativePath: specificationPath,
            completionReceiptRelativePath: completionReceiptRelativePath
        )
    }
}
