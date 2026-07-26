public struct RuntimeGuestOperationWaitConfiguration: Equatable, Sendable {
    public let maxAttempts: Int
    public let progressEveryAttempts: Int

    public init(maxAttempts: Int, progressEveryAttempts: Int) {
        self.maxAttempts = maxAttempts
        self.progressEveryAttempts = progressEveryAttempts
    }
}
