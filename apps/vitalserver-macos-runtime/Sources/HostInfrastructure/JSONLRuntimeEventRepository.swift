import Foundation
import Core
import Contracts

public struct JSONLRuntimeEventRepository: RuntimeEventRepository {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func append(_ event: RuntimeEventDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event) + Data("\n".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            handle.write(data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    public func recent(limit: Int) -> [RuntimeEventDocument] {
        guard limit > 0 else {
            return []
        }

        return Array(all().suffix(limit))
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        let filtered = all()
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
        return RuntimeEventPage(events: pageEvents, nextCursor: nextCursor(for: pageEvents, hasMore: filtered.count > pageEvents.count))
    }

    public func all() -> [RuntimeEventDocument] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(RuntimeEventDocument.self, from: Data(line.utf8))
            }
    }

    private func nextCursor(for events: [RuntimeEventDocument], hasMore: Bool) -> RuntimeEventCursor? {
        guard hasMore, let first = events.first else {
            return nil
        }
        return RuntimeEventCursor(timestamp: first.timestamp, id: first.id)
    }
}
