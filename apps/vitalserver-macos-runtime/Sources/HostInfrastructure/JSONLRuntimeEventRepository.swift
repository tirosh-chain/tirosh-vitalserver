import Foundation
import Core
import Contracts

public struct JSONLRuntimeEventRepository: RuntimeEventRepository {
    public static let defaultRotationMaxBytes: UInt64 = 16 * 1024 * 1024
    public static let defaultRotationKeepCount = 10

    public let url: URL
    private let rotationMaxBytes: UInt64
    private let rotationKeepCount: Int

    public init(
        url: URL,
        rotationMaxBytes: UInt64 = Self.defaultRotationMaxBytes,
        rotationKeepCount: Int = Self.defaultRotationKeepCount
    ) {
        self.url = url
        self.rotationMaxBytes = rotationMaxBytes
        self.rotationKeepCount = rotationKeepCount
    }

    public func append(_ event: RuntimeEventDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event) + Data("\n".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rotateIfNeeded(incomingBytes: UInt64(data.count))

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
        return RuntimeEventPage(
            events: pageEvents,
            nextCursor: nextCursor(for: pageEvents, hasMore: filtered.count > pageEvents.count),
            matchingCount: filtered.count
        )
    }

    public func all() -> [RuntimeEventDocument] {
        let decoder = JSONDecoder()
        return eventLogURLs()
            .flatMap { url -> [RuntimeEventDocument] in
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8)
                else {
                    return []
                }
                return text
                    .split(separator: "\n")
                    .compactMap { line in
                        try? decoder.decode(RuntimeEventDocument.self, from: Data(line.utf8))
                    }
            }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) throws {
        guard rotationKeepCount > 0,
              FileManager.default.fileExists(atPath: url.path),
              try fileSize(url) + incomingBytes >= rotationMaxBytes else {
            return
        }

        for index in stride(from: rotationKeepCount - 1, through: 1, by: -1) {
            let source = rotatedURL(index)
            let destination = rotatedURL(index + 1)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: destination)
            }
        }

        let firstRotated = rotatedURL(1)
        if FileManager.default.fileExists(atPath: firstRotated.path) {
            try FileManager.default.removeItem(at: firstRotated)
        }
        try FileManager.default.moveItem(at: url, to: firstRotated)
    }

    private func eventLogURLs() -> [URL] {
        var urls: [URL] = []
        if rotationKeepCount > 0 {
            for index in stride(from: rotationKeepCount, through: 1, by: -1) {
                let rotated = rotatedURL(index)
                if FileManager.default.fileExists(atPath: rotated.path) {
                    urls.append(rotated)
                }
            }
        }
        urls.append(url)
        return urls
    }

    private func rotatedURL(_ index: Int) -> URL {
        URL(fileURLWithPath: "\(url.path).\(index)")
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func nextCursor(for events: [RuntimeEventDocument], hasMore: Bool) -> RuntimeEventCursor? {
        guard hasMore, let first = events.first else {
            return nil
        }
        return RuntimeEventCursor(timestamp: first.timestamp, id: first.id)
    }
}
