import Contracts
import Foundation
import Errors

public enum RuntimePackageReceiptStateReader {
    public static func states(
        identifiers: [String],
        runProcess: (String, [String]) -> RuntimeProcessResult
    ) -> [RuntimePackageReceiptState] {
        identifiers.map { identifier in
            state(identifier: identifier, runProcess: runProcess)
        }
    }

    public static func state(
        identifier: String,
        runProcess: (String, [String]) -> RuntimeProcessResult
    ) -> RuntimePackageReceiptState {
        let result = runProcess("/usr/sbin/pkgutil", ["--pkg-info", identifier])
        if result.exitCode == 0 {
            return .present(identifier: identifier)
        }

        let message = processFailureReason(result)
        if message.lowercased().contains("no receipt") {
            return .absent(identifier: identifier)
        }
        return .readFailed(identifier: identifier, reason: message)
    }

    public static func processFailureReason(_ result: RuntimeProcessResult) -> String {
        RuntimeProcessFailureMessageFormatter.message(result)
    }
}
