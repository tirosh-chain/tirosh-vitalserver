import Contracts
import Foundation

enum RuntimeHostProxyListenerScanResultMapper {
    static func scanResult(from result: RuntimeProcessResult) -> RuntimeHostProxyListenerScanResult {
        guard result.exitCode == 0 else {
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 1,
               stdout.isEmpty,
               stderr.isEmpty,
               result.outputIssues.isEmpty {
                return .clear
            }
            return .commandFailed(
                exitCode: result.exitCode,
                reason: RuntimeProcessFailureMessageFormatter.message(result)
            )
        }

        do {
            let listeners = try RuntimeLsofListenerParser.parse(result.stdout)
            return listeners.isEmpty ? .clear : .loaded(listeners)
        } catch {
            return .malformedOutput(exitCode: result.exitCode, reason: String(describing: error))
        }
    }
}
