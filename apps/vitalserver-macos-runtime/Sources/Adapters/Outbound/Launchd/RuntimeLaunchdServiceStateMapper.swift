import Contracts
import Foundation

enum RuntimeLaunchdServiceStateMapper {
    static func state(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue]
    ) -> RuntimeServiceState {
        guard exitCode != 0 else {
            return .loaded
        }

        let message = commandFailureMessage(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            outputIssues: outputIssues
        )
        let lowercased = message.lowercased()
        if lowercased.contains("could not find service")
            || lowercased.contains("no such process")
            || lowercased.contains("not found")
        {
            return .notLoaded
        }
        if lowercased.contains("permission denied")
            || lowercased.contains("operation not permitted")
        {
            return .permissionDenied(message)
        }
        return .readFailed(message)
    }

    static func commandFailureMessage(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue]
    ) -> String {
        let stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(exitCode) stdout=\(stdout)"
        }
        let outputIssueSummary = outputIssues
            .map { "\($0.stream.rawValue): \($0.message)" }
            .joined(separator: "; ")
        if !outputIssueSummary.isEmpty {
            return "exitCode=\(exitCode) outputIssues=\(outputIssueSummary)"
        }
        return "exitCode=\(exitCode)"
    }
}
