import Contracts
import Domain

public enum VerifyUpdateBootstrapPayloadClosureError:
    Error,
    Equatable,
    Sendable
{
    case envelopeVerificationMismatch(expected: String, actual: String)
    case closureInvalid(UpdateBootstrapBundleClosureError)
    case artifactUnavailable(artifactId: String, reason: String)
    case artifactInspectionFailed(artifactId: String, reason: String)
    case artifactDigestMismatch(
        artifactId: String,
        expected: String,
        actual: String
    )
    case artifactSizeMismatch(
        artifactId: String,
        expected: Int,
        actual: Int
    )
}

public struct VerifyUpdateBootstrapPayloadClosureUseCase {
    public init() {}

    public func verify(
        envelope: UpdateBootstrapEnvelope,
        envelopeVerification: VerifiedUpdateBootstrapClosure,
        entries: [UpdateBootstrapBundleEntry],
        observeArtifact: (UpdateBootstrapArtifact)
            -> UpdateBootstrapArtifactObservation
    ) throws -> VerifiedUpdateBootstrapClosure {
        guard envelopeVerification.updateId == envelope.id else {
            throw VerifyUpdateBootstrapPayloadClosureError
                .envelopeVerificationMismatch(
                    expected: envelope.id,
                    actual: envelopeVerification.updateId
                )
        }
        do {
            try UpdateBootstrapBundleClosurePolicy.validateExact(
                envelope: envelope,
                entries: entries
            )
        } catch let error as UpdateBootstrapBundleClosureError {
            throw VerifyUpdateBootstrapPayloadClosureError
                .closureInvalid(error)
        }

        for artifact in envelope.payloadArtifacts {
            try verify(
                artifact,
                observation: observeArtifact(artifact)
            )
        }
        return VerifiedUpdateBootstrapClosure(
            updateId: envelopeVerification.updateId,
            canonicalPayloadSHA256:
                envelopeVerification.canonicalPayloadSHA256,
            verifiedBootstrapArtifactIds:
                envelopeVerification.verifiedBootstrapArtifactIds,
            verifiedPayloadArtifactIds: envelope.payloadArtifacts.map(\.id)
        )
    }

    private func verify(
        _ artifact: UpdateBootstrapArtifact,
        observation: UpdateBootstrapArtifactObservation
    ) throws {
        switch observation {
        case .available(let actualSHA256, let actualSizeBytes):
            guard actualSHA256 == artifact.sha256 else {
                throw VerifyUpdateBootstrapPayloadClosureError
                    .artifactDigestMismatch(
                        artifactId: artifact.id,
                        expected: artifact.sha256,
                        actual: actualSHA256
                    )
            }
            guard actualSizeBytes == artifact.sizeBytes else {
                throw VerifyUpdateBootstrapPayloadClosureError
                    .artifactSizeMismatch(
                        artifactId: artifact.id,
                        expected: artifact.sizeBytes,
                        actual: actualSizeBytes
                    )
            }
        case .unavailable(let reason):
            throw VerifyUpdateBootstrapPayloadClosureError
                .artifactUnavailable(
                    artifactId: artifact.id,
                    reason: reason
                )
        case .failed(let reason):
            throw VerifyUpdateBootstrapPayloadClosureError
                .artifactInspectionFailed(
                    artifactId: artifact.id,
                    reason: reason
                )
        }
    }
}
