import Foundation
import RuntimeCore

public struct JSONFileRuntimeStatusRepository: RuntimeStatusRepository {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> RuntimeStatusDocument? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(RuntimeStatusDocument.self, from: data)
    }

    public func save(_ document: RuntimeStatusDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
