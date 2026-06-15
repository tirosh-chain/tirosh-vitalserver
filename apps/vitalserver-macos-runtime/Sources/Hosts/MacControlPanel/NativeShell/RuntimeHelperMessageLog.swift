import Foundation
import Contracts
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
            let state = pathState(url)
            switch state {
            case .file:
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            case .missing:
                try Data(entry.utf8).write(to: url, options: .atomic)
            case .inspectFailed(let reason):
                throw RuntimeHelperMessageLogError.pathInspectionFailed(path: url.path, reason: reason)
            case .directory, .other, .unknown:
                throw RuntimeHelperMessageLogError.unexpectedPathState(path: url.path, state: state.rawValue)
            }
        } catch {
            fputs("Failed to append helper message log: \(error.localizedDescription)\n", stderr)
        }
    }

    private func reset() {
        let state = pathState(url)
        guard state == .file else {
            if state != .missing {
                fputs("Failed to reset helper message log: unexpected path state path=\(url.path) state=\(state.rawValue)\n", stderr)
            }
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

    private func pathState(_ url: URL) -> RuntimePathState {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return .other("missing-file-type")
            }
            switch type {
            case .typeRegular:
                return .file
            case .typeDirectory:
                return .directory
            default:
                return .other(type.rawValue)
            }
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
    }

    private func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}

private enum RuntimeHelperMessageLogError: LocalizedError {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)

    var errorDescription: String? {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            return "helper message log path inspection failed: \(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return "helper message log path state is unexpected: \(path) state=\(state)"
        }
    }
}
