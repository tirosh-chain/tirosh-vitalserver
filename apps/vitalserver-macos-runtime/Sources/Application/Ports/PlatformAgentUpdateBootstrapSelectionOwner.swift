public protocol PlatformAgentUpdateBootstrapSelectionOwning: Sendable {
    func recordVerifiedSelection(
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String,
        observedBundlePath: String,
        observedAt: String
    ) throws

    func bindApply(
        observedBundlePath: String,
        mintRequestId: @Sendable () -> String
    ) throws -> String

    func spendApply(requestId: String) throws
}
