import Contracts
import Domain

public enum AdvanceUpdateBootstrapJournalError: Error, Equatable, Sendable {
    case verificationUpdateMismatch(expected: String, actual: String)
    case verificationDigestMismatch(expected: String, actual: String)
    case verifiedArtifactSetMismatch(expected: [String], actual: [String])
}

public struct AdvanceUpdateBootstrapJournalUseCase {
    public init() {}

    public func verifiedAndStaged(
        journal: UpdateBootstrapJournal,
        verification: VerifiedUpdateBootstrapClosure,
        updaterRelativePath: String,
        specificationRelativePath: String,
        observedAt: String
    ) throws -> UpdateBootstrapJournal {
        guard verification.updateId == journal.envelope.id else {
            throw AdvanceUpdateBootstrapJournalError.verificationUpdateMismatch(
                expected: journal.envelope.id,
                actual: verification.updateId
            )
        }
        guard verification.canonicalPayloadSHA256
                == journal.bootstrapSignedSHA256 else {
            throw AdvanceUpdateBootstrapJournalError.verificationDigestMismatch(
                expected: journal.bootstrapSignedSHA256,
                actual: verification.canonicalPayloadSHA256
            )
        }
        let expectedArtifacts = [
            journal.envelope.nextUpdaterArtifact.id,
            journal.envelope.specification.id,
        ].sorted()
        let actualArtifacts = verification.verifiedArtifactIds.sorted()
        guard actualArtifacts == expectedArtifacts else {
            throw AdvanceUpdateBootstrapJournalError
                .verifiedArtifactSetMismatch(
                    expected: expectedArtifacts,
                    actual: actualArtifacts
                )
        }
        return try UpdateBootstrapJournalStateMachine.transition(
            journal: journal,
            event: .verifiedAndStaged(
                updaterRelativePath: updaterRelativePath,
                specificationRelativePath: specificationRelativePath,
                observedAt: observedAt
            )
        )
    }

    public func handoffStarted(
        journal: UpdateBootstrapJournal,
        observedAt: String
    ) throws -> UpdateBootstrapJournal {
        try UpdateBootstrapJournalStateMachine.transition(
            journal: journal,
            event: .handoffStarted(observedAt: observedAt)
        )
    }

    public func failed(
        journal: UpdateBootstrapJournal,
        reason: String,
        observedAt: String
    ) throws -> UpdateBootstrapJournal {
        try UpdateBootstrapJournalStateMachine.transition(
            journal: journal,
            event: .failed(reason: reason, observedAt: observedAt)
        )
    }
}
