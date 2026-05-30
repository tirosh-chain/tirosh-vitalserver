import Foundation
import Core
import Contracts

public struct JSONFileRuntimeStatusRepository: RuntimeStatusRepository {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadResult() -> RuntimeStatusDocumentLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        do {
            let data = try Data(contentsOf: url)
            return try .loaded(JSONDecoder().decode(RuntimeStatusDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func save(_ document: RuntimeStatusDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
