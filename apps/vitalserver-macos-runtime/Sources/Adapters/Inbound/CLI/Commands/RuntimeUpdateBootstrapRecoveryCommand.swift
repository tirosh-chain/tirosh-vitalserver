public struct RuntimeUpdateBootstrapRecoveryCommand: Equatable, Sendable {
    public let updateId: String

    public init(updateId: String) {
        self.updateId = updateId
    }
}

public struct RuntimeFailUpdateBootstrapCommand: Equatable, Sendable {
    public let updateId: String
    public let reason: String

    public init(updateId: String, reason: String) {
        self.updateId = updateId
        self.reason = reason
    }
}
