import Contracts

public enum UpdateBootstrapAdmissionError: Error, Equatable, Sendable {
    case verificationUpdateMismatch(expected: String, actual: String)
    case verificationDigestMismatch(expected: String, actual: String)
    case verifiedArtifactSetMismatch(expected: [String], actual: [String])
}

public enum UpdateBootstrapAdmissionPolicy {
    public static func admit(
        envelope: UpdateBootstrapEnvelope,
        verification: VerifiedUpdateBootstrapClosure,
        operationId: String,
        installedRelease: InstalledProductRelease,
        requestId: String,
        admittedAt: String
    ) throws -> UpdateBootstrapJournal {
        guard verification.updateId == envelope.id else {
            throw UpdateBootstrapAdmissionError.verificationUpdateMismatch(
                expected: envelope.id,
                actual: verification.updateId
            )
        }
        guard verification.canonicalPayloadSHA256
                == envelope.signature.signedSha256 else {
            throw UpdateBootstrapAdmissionError.verificationDigestMismatch(
                expected: envelope.signature.signedSha256,
                actual: verification.canonicalPayloadSHA256
            )
        }
        let expectedArtifacts = [
            envelope.nextUpdaterArtifact.id,
            envelope.specification.id,
        ].sorted()
        let actualArtifacts = verification.verifiedArtifactIds.sorted()
        guard actualArtifacts == expectedArtifacts else {
            throw UpdateBootstrapAdmissionError.verifiedArtifactSetMismatch(
                expected: expectedArtifacts,
                actual: actualArtifacts
            )
        }

        let journal = UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: envelope.id,
            journalRevision: 1,
            operationId: operationId,
            targetInstallationId: installedRelease.installationId,
            expectedInstallationRevision: installedRelease.installationRevision,
            requestId: requestId,
            envelope: envelope,
            bootstrapSignedSHA256: verification.canonicalPayloadSHA256,
            state: .admitted,
            stagedUpdaterRelativePath: nil,
            stagedSpecificationRelativePath: nil,
            completion: nil,
            failureReason: nil,
            createdAt: admittedAt,
            updatedAt: admittedAt
        )
        try UpdateBootstrapJournalPolicy.validate(journal)
        return journal
    }
}
