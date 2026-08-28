public struct VerifiedUpdateBootstrapClosure: Equatable, Sendable {
    public let updateId: String
    public let canonicalPayloadSHA256: String
    public let verifiedBootstrapArtifactIds: [String]
    public let verifiedPayloadArtifactIds: [String]

    public init(
        updateId: String,
        canonicalPayloadSHA256: String,
        verifiedBootstrapArtifactIds: [String],
        verifiedPayloadArtifactIds: [String]
    ) {
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
        self.verifiedBootstrapArtifactIds = verifiedBootstrapArtifactIds
        self.verifiedPayloadArtifactIds = verifiedPayloadArtifactIds
    }
}
