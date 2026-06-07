import Foundation
import Application
import Contracts
import Errors

public struct CurlRuntimeHTTPProber: RuntimeHTTPProber {
    private let commandRunner: RuntimeCommandRunner

    public init(commandRunner: RuntimeCommandRunner) {
        self.commandRunner = commandRunner
    }

    public func statusCode(url: String) -> String {
        statusRead(url: url).statusText
    }

    public func statusRead(url: String) -> RuntimeHTTPProbeResult {
        let result = commandRunner.run(
            "/usr/bin/curl",
            arguments: ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0, !code.isEmpty, result.outputIssues.isEmpty {
            return .reportedStatus(code)
        }
        if !result.outputIssues.isEmpty {
            return .outputInvalid(processFailureReason(result))
        }
        if result.exitCode == 0, code.isEmpty {
            return .emptyStatus
        }
        return .commandFailed(processFailureReason(result))
    }

    private func processFailureReason(_ result: RuntimeProcessResult) -> String {
        RuntimeProcessFailureMessageFormatter.message(result)
    }
}
