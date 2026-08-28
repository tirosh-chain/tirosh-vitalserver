import Application

public struct RuntimeProveUpdateBootstrapCommand: Equatable, Sendable {
    public let updateId: String
    public let expectation: UpdateBootstrapLifecycleProofExpectation
    public let timeoutMilliseconds: UInt64
    public let pollIntervalMilliseconds: UInt64
    public let requirePlatformAgentVerification: Bool

    public init(
        updateId: String,
        expectation: UpdateBootstrapLifecycleProofExpectation,
        timeoutMilliseconds: UInt64,
        pollIntervalMilliseconds: UInt64,
        requirePlatformAgentVerification: Bool = false
    ) {
        self.updateId = updateId
        self.expectation = expectation
        self.timeoutMilliseconds = timeoutMilliseconds
        self.pollIntervalMilliseconds = pollIntervalMilliseconds
        self.requirePlatformAgentVerification = requirePlatformAgentVerification
    }
}
