import Foundation
import Application
import Contracts
import Errors

public struct JSONLRuntimeEventRepository: RuntimeEventRepository {
    public static let defaultRotationMaxBytes: UInt64 = 16 * 1024 * 1024
    public static let defaultRotationKeepCount = 10

    public let url: URL
    private let rotationMaxBytes: UInt64
    private let rotationKeepCount: Int
    private let fileStore: RuntimeFileStore

    public init(
        url: URL,
        rotationMaxBytes: UInt64 = Self.defaultRotationMaxBytes,
        rotationKeepCount: Int = Self.defaultRotationKeepCount,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) {
        self.url = url
        self.rotationMaxBytes = rotationMaxBytes
        self.rotationKeepCount = rotationKeepCount
        self.fileStore = fileStore
    }

    public func append(_ event: RuntimeEventDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event) + Data("\n".utf8)
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rotateIfNeeded(incomingBytes: UInt64(data.count))

        if try eventLogFileIsPresent(url) {
            try fileStore.writeData(try fileStore.readData(url) + data, to: url, options: .atomic)
        } else {
            try fileStore.writeData(data, to: url, options: .atomic)
        }
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        let readResult = allResult()
        let filtered = readResult.events
            .filter { event in
                guard let eventType = query.eventType else {
                    return true
                }
                return event.eventType == eventType
            }
            .filter { event in
                guard let since = query.since else {
                    return true
                }
                return event.timestamp >= since
            }
            .filter { event in
                guard let before = query.before else {
                    return true
                }
                return event.timestamp < before.timestamp
                    || (event.timestamp == before.timestamp && event.id < before.id)
            }
        let pageEvents = Array(filtered.suffix(query.limit))
        return RuntimeEventPage(
            events: pageEvents,
            nextCursor: nextCursor(for: pageEvents, hasMore: filtered.count > pageEvents.count),
            matchingCount: filtered.count,
            readError: readResult.issues.isEmpty
                ? nil
                : readResult.issues.map(String.init(describing:)).joined(separator: "; ")
        )
    }

    public func allResult() -> JSONLRuntimeEventReadResult {
        let decoder = JSONDecoder()
        var events: [RuntimeEventDocument] = []
        var issues: [JSONLRuntimeEventReadIssue] = []
        for url in eventLogCandidates() {
            let state = pathState(at: url)
            switch state {
            case .file:
                break
            case .missing:
                continue
            case .inspectFailed(let reason):
                issues.append(.pathInspectionFailed(path: url.path, message: reason))
                continue
            case .directory, .other, .unknown:
                issues.append(.unexpectedPathState(path: url.path, state: state.rawValue))
                continue
            }
            do {
                let data = try fileStore.readData(url)
                guard let text = String(data: data, encoding: .utf8) else {
                    issues.append(.invalidEncoding(path: url.path))
                    continue
                }
                let decoded = text
                    .split(separator: "\n")
                    .enumerated()
                    .compactMap { index, line -> RuntimeEventDocument? in
                        do {
                            return try decoder.decode(RuntimeEventDocument.self, from: Data(line.utf8))
                        } catch {
                            issues.append(.invalidLine(path: url.path, line: index + 1, message: error.localizedDescription))
                            return nil
                        }
                    }
                events.append(contentsOf: decoded)
            } catch {
                issues.append(.readFailed(path: url.path, message: error.localizedDescription))
            }
        }
        return JSONLRuntimeEventReadResult(events: events, issues: issues)
    }

    private func rotateIfNeeded(incomingBytes: UInt64) throws {
        guard rotationKeepCount > 0,
              try eventLogFileIsPresent(url),
              try fileSize(url) + incomingBytes >= rotationMaxBytes else {
            return
        }

        for index in stride(from: rotationKeepCount - 1, through: 1, by: -1) {
            let source = rotatedURL(index)
            let destination = rotatedURL(index + 1)
            if try eventLogFileIsPresent(destination) {
                try fileStore.removeItem(at: destination)
            }
            if try eventLogFileIsPresent(source) {
                try fileStore.moveItem(at: source, to: destination)
            }
        }

        let firstRotated = rotatedURL(1)
        if try eventLogFileIsPresent(firstRotated) {
            try fileStore.removeItem(at: firstRotated)
        }
        try fileStore.moveItem(at: url, to: firstRotated)
    }

    private func eventLogCandidates() -> [URL] {
        var urls: [URL] = []
        if rotationKeepCount > 0 {
            for index in stride(from: rotationKeepCount, through: 1, by: -1) {
                urls.append(rotatedURL(index))
            }
        }
        urls.append(url)
        return urls
    }

    private func rotatedURL(_ index: Int) -> URL {
        URL(fileURLWithPath: "\(url.path).\(index)")
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    private func eventLogFileIsPresent(_ url: URL) throws -> Bool {
        let state = pathState(at: url)
        switch state {
        case .file:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw JSONLRuntimeEventRepositoryError.pathInspectionFailed(path: url.path, reason: reason)
        case .directory, .other, .unknown:
            throw JSONLRuntimeEventRepositoryError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }

    private func pathState(at url: URL) -> RuntimePathState {
        fileStore.pathState(at: url)
    }

    private func nextCursor(for events: [RuntimeEventDocument], hasMore: Bool) -> RuntimeEventCursor? {
        guard hasMore, let first = events.first else {
            return nil
        }
        return RuntimeEventCursor(timestamp: first.timestamp, id: first.id)
    }
}

public struct JSONLRuntimeEventReadResult: Equatable, Sendable {
    public let events: [RuntimeEventDocument]
    public let issues: [JSONLRuntimeEventReadIssue]

    public init(events: [RuntimeEventDocument], issues: [JSONLRuntimeEventReadIssue]) {
        self.events = events
        self.issues = issues
    }
}

public enum JSONLRuntimeEventReadIssue: Equatable, Sendable {
    case pathInspectionFailed(path: String, message: String)
    case unexpectedPathState(path: String, state: String)
    case readFailed(path: String, message: String)
    case invalidEncoding(path: String)
    case invalidLine(path: String, line: Int, message: String)
}
