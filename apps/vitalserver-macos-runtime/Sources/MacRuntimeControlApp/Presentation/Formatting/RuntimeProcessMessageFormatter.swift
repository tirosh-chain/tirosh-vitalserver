import Foundation
import RuntimeControl

struct RuntimeProcessMessageFormatter {
    func summary(_ result: RuntimeCommandResult) -> String {
        let output = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if output.isEmpty {
            return result.exitCode == 0
                ? AppConstants.StatusText.done
                : AppConstants.StatusText.commandFailed(exitCode: result.exitCode)
        }
        return output
    }

    func message(title: String, result: RuntimeCommandResult) -> String {
        let output = summary(result).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, output != AppConstants.StatusText.done else {
            return title
        }
        if output == title || output.hasPrefix("\(title)\n") {
            return output
        }
        return "\(title)\n\n\(output)"
    }
}
