import Foundation
import Application
import Contracts

public struct JSONFileRuntimeGuestDocumentReader: RuntimeGuestBootstrapResultReader {
    public let bootstrapResultURL: URL
    private let fileStore: RuntimeFileReading & RuntimeFileWriting

    public init(
        bootstrapResultURL: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.bootstrapResultURL = bootstrapResultURL
        self.fileStore = fileStore
    }

    public func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> {
        decode(GuestBootstrapResultDocument.self, from: bootstrapResultURL)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> RuntimeGuestDocumentLoadResult<T> {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("runtime guest document path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("runtime guest document path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(type, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
