public struct RuntimeGuestWaitResultPlan: Equatable, Sendable {
    public let logMessage: String?
    public let failureMessage: String?

    public init(logMessage: String?, failureMessage: String?) {
        self.logMessage = logMessage
        self.failureMessage = failureMessage
    }
}

public enum RuntimeGuestWaitResultExecutionPlan: Equatable, Sendable {
    case completed(logMessage: String)
    case failed(logMessage: String, failureMessage: String)
    case failedWithoutLog(failureMessage: String)
}
