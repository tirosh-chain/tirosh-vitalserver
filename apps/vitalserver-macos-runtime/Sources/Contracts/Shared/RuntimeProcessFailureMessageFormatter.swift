import Foundation

public enum RuntimeProcessFailureMessageFormatter {
    public static func message(_ result: RuntimeProcessResult) -> String {
        message(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            outputIssues: result.outputIssues,
            executionIssue: result.executionIssue
        )
    }

    public static func message(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue],
        executionIssue: RuntimeProcessExecutionIssue?
    ) -> String {
        if let executionIssue {
            return "exitCode=\(exitCode) executionIssue=\(executionIssue.kind.rawValue): \(executionIssue.message)"
        }

        var parts = ["exitCode=\(exitCode)"]
        let stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            parts.append("stderr=\(stderr)")
        }
        if !stdout.isEmpty {
            parts.append("stdout=\(stdout)")
        }

        let outputIssues = outputIssues
            .map { "\($0.stream.rawValue):\($0.message)" }
            .joined(separator: ",")
        if !outputIssues.isEmpty {
            parts.append("outputIssues=\(outputIssues)")
        }

        return parts.joined(separator: " ")
    }
}
