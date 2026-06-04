public struct RuntimeInstallProvisionPayloadDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let passed: Bool
    public let blockers: [String]
    public let artifactStates: [RuntimeInstallArtifactState]

    public init(
        schemaVersion: Int = 1,
        passed: Bool,
        blockers: [String],
        artifactStates: [RuntimeInstallArtifactState]
    ) {
        self.schemaVersion = schemaVersion
        self.passed = passed
        self.blockers = blockers
        self.artifactStates = artifactStates
    }
}
