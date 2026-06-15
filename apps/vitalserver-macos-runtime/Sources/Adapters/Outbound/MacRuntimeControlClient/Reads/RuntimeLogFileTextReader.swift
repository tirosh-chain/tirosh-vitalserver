import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

struct RuntimeLogFileTextReader {
    private static let readByteLimit: UInt64 = 128 * 1024

    private let fileStore: RuntimeFileStore

    init(fileStore: RuntimeFileStore) {
        self.fileStore = fileStore
    }

    func read(_ source: RuntimeLogFileSource, lineLimit: Int) -> RuntimeHostTextReadResult {
        let selectedURL: URL
        switch selectedReadableURL(primaryPath: source.path, sourcePath: source.sourcePath) {
        case .loaded(let url):
            selectedURL = url
        case .missing(let message):
            return .missing(.message(message))
        case .failed(let message):
            return .failed(message)
        }

        let content: String?
        do {
            content = try readTailText(selectedURL)
        } catch {
            return .failed("Failed to read log file \(selectedURL.path): \(error.localizedDescription)")
        }
        guard let content else {
            return .missing(.noData)
        }
        let body = tail(content, lineLimit: lineLimit)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missing(.noData)
        }
        return .loaded(body)
    }

    func primaryFileIsMissing(_ source: RuntimeLogFileSource) -> Bool {
        fileStore.pathState(at: URL(fileURLWithPath: source.path)) == .missing
    }

    private func selectedReadableURL(
        primaryPath: String,
        sourcePath: String?
    ) -> RuntimeLogFileSelectionResult {
        let primaryURL = URL(fileURLWithPath: primaryPath)
        let primaryState = fileStore.pathState(at: primaryURL)
        switch primaryState {
        case .file:
            return .loaded(primaryURL)
        case .missing:
            break
        case .inspectFailed(let reason):
            return .failed("Log file path inspection failed \(primaryURL.path): \(reason)")
        case .directory, .other, .unknown:
            return .failed("Log file path state is unexpected \(primaryURL.path): \(primaryState.rawValue)")
        }

        guard let sourcePath else {
            return .missing("Log file is missing path=\(primaryURL.path)")
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sourceState = fileStore.pathState(at: sourceURL)
        switch sourceState {
        case .file:
            return .loaded(sourceURL)
        case .missing:
            return .missing("Log files are missing primary=\(primaryURL.path) source=\(sourceURL.path)")
        case .inspectFailed(let reason):
            return .failed("Log file path inspection failed \(sourceURL.path): \(reason)")
        case .directory, .other, .unknown:
            return .failed("Log file path state is unexpected \(sourceURL.path): \(sourceState.rawValue)")
        }
    }

    private func tail(_ content: String, lineLimit: Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }

    private func readTailText(_ url: URL) throws -> String? {
        let fileSize = try fileStore.fileSize(url)
        let offset = fileSize > Self.readByteLimit
            ? fileSize - Self.readByteLimit
            : nil
        let data: Data
        if let partialReader = fileStore as? RuntimeFilePartialReading {
            data = try partialReader.readData(url, offset: offset)
        } else {
            data = try fileStore.readData(url)
        }
        guard !data.isEmpty else {
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RuntimeHostFileReaderError.invalidUTF8(path: url.path)
        }
        return text
    }
}

private enum RuntimeLogFileSelectionResult {
    case loaded(URL)
    case missing(String)
    case failed(String)
}
