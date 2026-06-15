import Contracts
import Foundation

struct RuntimeHostProxyNginxCommandLineReader {
    var psPath: String
    var runProcess: (String, [String]) -> RuntimeProcessResult

    func read(pid: String) -> RuntimeHostProxyNginxCommandLineReadResult {
        let result = runProcess(psPath, ["-p", pid, "-o", "command="])
        guard result.exitCode == 0 else {
            return .readFailed(RuntimeProcessFailureMessageFormatter.message(result))
        }
        let commandLine = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandLine.isEmpty else {
            return .empty
        }
        return .loaded(commandLine)
    }
}
