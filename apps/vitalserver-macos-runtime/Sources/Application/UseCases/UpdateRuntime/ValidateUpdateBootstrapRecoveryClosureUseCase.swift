import Contracts

public enum ValidateUpdateBootstrapRecoveryClosureError:
    Error,
    Equatable,
    Sendable
{
    case envelopeMismatch
    case verificationUpdateMismatch(expected: String, actual: String)
    case verificationDigestMismatch(expected: String, actual: String)
    case verifiedArtifactSetMismatch(expected: [String], actual: [String])
    case verifiedPayloadArtifactSetMismatch(expected: [String], actual: [String])
}
public struct ValidateUpdateBootstrapRecoveryClosureUseCase {
    public init() {}

    public func validate(
        journal: UpdateBootstrapJournal,
        stagedEnvelope: UpdateBootstrapEnvelope,
        verification: VerifiedUpdateBootstrapClosure
    ) throws {
        guard stagedEnvelope == journal.envelope else {
            throw ValidateUpdateBootstrapRecoveryClosureError.envelopeMismatch
        }
        guard verification.updateId == journal.envelope.id else {
            throw ValidateUpdateBootstrapRecoveryClosureError
                .verificationUpdateMismatch(
                    expected: journal.envelope.id,
                    actual: verification.updateId
                )
        }
        guard verification.canonicalPayloadSHA256
                == journal.bootstrapSignedSHA256 else {
            throw ValidateUpdateBootstrapRecoveryClosureError
                .verificationDigestMismatch(
                    expected: journal.bootstrapSignedSHA256,
                    actual: verification.canonicalPayloadSHA256
                )
        }
        let expectedArtifacts = [
            journal.envelope.nextUpdaterArtifact.id,
            journal.envelope.specification.id,
        ].sorted()
        let actualArtifacts =
            verification.verifiedBootstrapArtifactIds.sorted()
        guard actualArtifacts == expectedArtifacts else {
            throw ValidateUpdateBootstrapRecoveryClosureError
                .verifiedArtifactSetMismatch(
                    expected: expectedArtifacts,
                    actual: actualArtifacts
                )
        }
        let expectedPayloadArtifacts =
            journal.envelope.payloadArtifacts.map(\.id).sorted()
        let actualPayloadArtifacts =
            verification.verifiedPayloadArtifactIds.sorted()
        guard actualPayloadArtifacts == expectedPayloadArtifacts else {
            throw ValidateUpdateBootstrapRecoveryClosureError
                .verifiedPayloadArtifactSetMismatch(
                    expected: expectedPayloadArtifacts,
                    actual: actualPayloadArtifacts
                )
        }
    }
}
