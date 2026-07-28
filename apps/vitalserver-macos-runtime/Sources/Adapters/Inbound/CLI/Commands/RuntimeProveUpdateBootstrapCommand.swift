import Application

public struct RuntimeProveUpdateBootstrapCommand: Equatable, Sendable {
    public let updateId: String
    public let expectation: UpdateBootstrapLifecycleProofExpectation
    public let timeoutMilliseconds: UInt64
    public let pollIntervalMilliseconds: UInt64

    public init(
        updateId: String,
        expectation: UpdateBootstrapLifecycleProofExpectation,
        timeoutMilliseconds: UInt64,
        pollIntervalMilliseconds: UInt64
    ) {
        self.updateId = updateId
        self.expectation = expectation
        self.timeoutMilliseconds = timeoutMilliseconds
        self.pollIntervalMilliseconds = pollIntervalMilliseconds
    }
}
