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
        guard limit > 0,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line in
                try? decoder.decode(RuntimeEventDocument.self, from: Data(line.utf8))
            }
    }
}
