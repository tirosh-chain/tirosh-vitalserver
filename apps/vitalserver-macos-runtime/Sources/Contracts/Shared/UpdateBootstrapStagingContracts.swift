import Foundation

public struct UpdateBootstrapStagingInput: Equatable, Sendable {
    public let updateId: String
    public let stagingAttemptId: String
    public let sourceBundle: URL

    public init(
        updateId: String,
        stagingAttemptId: String,
        sourceBundle: URL
    ) {
        self.updateId = updateId
        self.stagingAttemptId = stagingAttemptId
        self.sourceBundle = sourceBundle
    }
}

public struct StagedUpdateBootstrapBundle: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }
}
