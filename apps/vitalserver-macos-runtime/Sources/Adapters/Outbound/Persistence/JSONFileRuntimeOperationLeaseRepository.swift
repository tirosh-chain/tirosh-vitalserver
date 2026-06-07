import Application
import Contracts
import Errors
import Foundation

public struct JSONFileRuntimeOperationLeaseRepository: RuntimeOperationLeaseRepository {
    public let url: URL
    private let fileStore: RuntimeFileReading & RuntimeFileWriting

    public init(
        url: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.url = url
        self.fileStore = fileStore
    }

    public func loadResult() -> RuntimeOperationLeaseLoadResult {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("runtime operation lease path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("runtime operation lease path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(RuntimeOperationLeaseDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        switch loadResult() {
        case .missing:
            break
        case .loaded(let existing):
            throw RuntimeOperationLeaseRepositoryError.existingOperation(
                operationId: existing.operationId,
                operation: existing.operation.rawValue
            )
        case .failed(let reason):
            throw RuntimeOperationLeaseRepositoryError.readFailed(reason)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(data, to: url, options: .atomic)
    }

    public func release(operationId: String) throws {
        switch loadResult() {
        case .missing:
            return
        case .loaded(let existing):
            guard existing.operationId == operationId else {
                throw RuntimeOperationLeaseRepositoryError.operationIdMismatch(
                    expected: operationId,
                    actual: existing.operationId
                )
            }
            try fileStore.removeItem(at: url)
        case .failed(let reason):
            throw RuntimeOperationLeaseRepositoryError.readFailed(reason)
        }
    }
}
