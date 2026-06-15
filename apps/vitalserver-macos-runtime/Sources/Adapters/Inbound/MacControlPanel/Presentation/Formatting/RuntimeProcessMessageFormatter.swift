import Foundation
import RuntimeControl
import Errors

public protocol RuntimeProcessMessageVocabulary {
    var doneText: String { get }
    func commandFailedText(exitCode: Int32) -> String
}

public struct DefaultRuntimeProcessMessageVocabulary: RuntimeProcessMessageVocabulary {
    public init() {}

    public var doneText: String {
        "Done"
    }

    public func commandFailedText(exitCode: Int32) -> String {
        "Command failed with exit code \(exitCode)"
    }
}

public struct RuntimeProcessMessageFormatter {
    private let vocabulary: RuntimeProcessMessageVocabulary

    public init(vocabulary: RuntimeProcessMessageVocabulary = DefaultRuntimeProcessMessageVocabulary()) {
        self.vocabulary = vocabulary
    }

    public func summary(_ result: RuntimeCommandResult) -> String {
        let output = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if output.isEmpty {
            return result.exitCode == 0
                ? vocabulary.doneText
                : vocabulary.commandFailedText(exitCode: result.exitCode)
        }
        return output
    }

    public func message(title: String, result: RuntimeCommandResult) -> String {
        let output = summary(result).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, output != vocabulary.doneText else {
            return title
        }
        if output == title || output.hasPrefix("\(title)\n") {
            return output
        }
        return "\(title)\n\n\(output)"
    }
}
