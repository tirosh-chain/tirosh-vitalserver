import Foundation
import OutboundAdapters
import InboundAdapters
import Errors

struct FileRuntimeHelperMessageLog: RuntimeHelperMessageLogging {
    let url: URL
    var now: @Sendable () -> Date = Date.init

    init(
        url: URL = InstalledRuntimePaths.defaultInstalled.managerHelperMessageLog,
        now: @escaping @Sendable () -> Date = Date.init,
        resetExistingLog: Bool = true
    ) {
        self.url = url
        self.now = now
        if resetExistingLog {
            reset()
        }
    }

    func append(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let entry = "[\(Self.timestamp(now()))] \(Self.indented(trimmed))\n"
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            } else {
                try Data(entry.utf8).write(to: url, options: .atomic)
            }
        } catch {
            fputs("Failed to append helper message log: \(error.localizedDescription)\n", stderr)
        }
    }

    private func reset() {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            fputs("Failed to reset helper message log: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func indented(_ message: String) -> String {
        message.replacingOccurrences(of: "\n", with: "\n  ")
    }
}
