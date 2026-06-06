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
        let result = commandRunner.run(
            "/usr/bin/curl",
            arguments: ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !code.isEmpty ? code : "failed"
    }
}
