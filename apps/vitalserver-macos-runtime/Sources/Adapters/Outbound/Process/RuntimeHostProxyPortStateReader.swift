import Contracts
import Foundation
import Errors

public enum RuntimeHostProxyPortStateReader {
    public static func state(
        port: Int,
        lsofPath: String,
        runProcess: (String, [String]) -> RuntimeProcessResult
    ) -> RuntimeHostProxyPortState {
        let result = runProcess(lsofPath, ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        if result.exitCode == 0 {
            let listeners = parsedListeners(result.stdout)
            return listeners.isEmpty
                ? .clear(port: port)
                : .occupied(port: port, listeners: listeners.joined(separator: ","))
        }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 1, stdout.isEmpty, stderr.isEmpty {
            return .clear(port: port)
        }
        return .inspectFailed(port: port, reason: processFailureReason(result))
    }

    private static func parsedListeners(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> String? in
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2 else {
                    return nil
                }
                return "\(fields[0])/\(fields[1])"
            }
            .sorted()
    }

    private static func processFailureReason(_ result: RuntimeProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(result.exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(result.exitCode) stdout=\(stdout)"
        }
        return "exitCode=\(result.exitCode)"
    }
}
