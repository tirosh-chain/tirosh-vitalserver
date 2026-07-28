import Application

public struct RuntimeProveUpdateBootstrapCommand: Equatable, Sendable {
    public let updateId: String
    public let expectation: UpdateBootstrapLifecycleProofExpectation

    public init(
        updateId: String,
        expectation: UpdateBootstrapLifecycleProofExpectation
    ) {
        self.updateId = updateId
        self.expectation = expectation
    }
}
