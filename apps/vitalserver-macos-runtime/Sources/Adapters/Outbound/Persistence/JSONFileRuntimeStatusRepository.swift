import Foundation
import Application
import Contracts
import Errors

public struct JSONFileRuntimeStatusRepository: RuntimeStatusRepository {
    public let url: URL
    private let fileStore: RuntimeFileReading & RuntimeFileWriting

    public init(
        url: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.url = url
        self.fileStore = fileStore
    }

    public func loadResult() -> RuntimeStatusDocumentLoadResult {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("runtime status document path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("runtime status document path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(RuntimeStatusDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func save(_ document: RuntimeStatusDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(data, to: url, options: .atomic)
    }
}
