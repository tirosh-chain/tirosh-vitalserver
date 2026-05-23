import Foundation
import Core
import Contracts

struct CurlRuntimeHTTPProber: RuntimeHTTPProber {
    private let commandRunner: RuntimeCommandRunner

    init(commandRunner: RuntimeCommandRunner) {
        self.commandRunner = commandRunner
    }

    func statusCode(url: String) -> String {
        let result = commandRunner.run(
            Constants.Commands.curl,
            arguments: ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !code.isEmpty ? code : "failed"
    }
}
