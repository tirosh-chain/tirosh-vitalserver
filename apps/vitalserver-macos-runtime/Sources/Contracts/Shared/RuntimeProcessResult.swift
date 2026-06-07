public enum RuntimeProcessExecutionIssueKind: String, Codable, Equatable, Sendable {
    case processLaunchFailed
    case outputFilePreparationFailed
}

public struct RuntimeProcessExecutionIssue: Codable, Equatable, Sendable {
    public let kind: RuntimeProcessExecutionIssueKind
    public let message: String

    public init(kind: RuntimeProcessExecutionIssueKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct RuntimeProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let outputIssues: [RuntimeCommandOutputIssue]
    public let executionIssue: RuntimeProcessExecutionIssue?

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue] = [],
        executionIssue: RuntimeProcessExecutionIssue? = nil
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.outputIssues = outputIssues
        self.executionIssue = executionIssue
    }
}
