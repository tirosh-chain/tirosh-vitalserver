import Foundation
import Contracts
import RuntimeControl

struct RuntimeLogExportIssues {
    var collectionIssue: String?
    var supplementalIssues: [String: String] = [:]
    var rotatedIssues: [String: String] = [:]
    var rotatedCopiedCounts: [String: Int] = [:]
}

extension RuntimeCommandResult {
    var localSummary: String {
        let output = [stdout, stderr, outputIssues.localSummary]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if output.isEmpty {
            return exitCode == 0
                ? "Done"
                : "Command failed with exit code \(exitCode)"
        }
        return output
    }
}

private extension Array where Element == RuntimeCommandOutputIssue {
    var localSummary: String {
        map { "\($0.stream.rawValue): \($0.message)" }
            .joined(separator: "\n")
    }
}
