import Contracts

public enum UpdateBootstrapStagedProofError: Error, Equatable, Sendable {
    case updateMismatch(expected: String, actual: String)
    case canonicalPayloadDigestMismatch(expected: String, actual: String)
    case bootstrapArtifactSetMismatch(expected: [String], actual: [String])
    case payloadArtifactSetMismatch(expected: [String], actual: [String])
}

public enum UpdateBootstrapStagedProofPolicy {
    public static func requireMatch(
        source: VerifiedUpdateBootstrapClosure,
        staged: VerifiedUpdateBootstrapClosure
    ) throws {
        guard staged.updateId == source.updateId else {
            throw UpdateBootstrapStagedProofError.updateMismatch(
                expected: source.updateId,
                actual: staged.updateId
            )
        }
        guard staged.canonicalPayloadSHA256 == source.canonicalPayloadSHA256 else {
            throw UpdateBootstrapStagedProofError
                .canonicalPayloadDigestMismatch(
                    expected: source.canonicalPayloadSHA256,
                    actual: staged.canonicalPayloadSHA256
                )
        }
        guard staged.verifiedBootstrapArtifactIds.sorted()
                == source.verifiedBootstrapArtifactIds.sorted() else {
            throw UpdateBootstrapStagedProofError.bootstrapArtifactSetMismatch(
                expected: source.verifiedBootstrapArtifactIds.sorted(),
                actual: staged.verifiedBootstrapArtifactIds.sorted()
            )
        }
        guard staged.verifiedPayloadArtifactIds.sorted()
                == source.verifiedPayloadArtifactIds.sorted() else {
            throw UpdateBootstrapStagedProofError.payloadArtifactSetMismatch(
                expected: source.verifiedPayloadArtifactIds.sorted(),
                actual: staged.verifiedPayloadArtifactIds.sorted()
            )
        }
    }
}
