public struct VerifiedUpdateBootstrapClosure: Equatable, Sendable {
    public let updateId: String
    public let canonicalPayloadSHA256: String
    public let verifiedArtifactIds: [String]

    public init(
        updateId: String,
        canonicalPayloadSHA256: String,
        verifiedArtifactIds: [String]
    ) {
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
        self.verifiedArtifactIds = verifiedArtifactIds
    }
}
