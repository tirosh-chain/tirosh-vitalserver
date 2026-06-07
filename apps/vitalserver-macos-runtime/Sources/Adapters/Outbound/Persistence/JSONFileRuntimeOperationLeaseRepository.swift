import Application
import Contracts
import Errors
import Foundation

public struct JSONFileRuntimeOperationLeaseRepository: RuntimeOperationLeaseRepository {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadResult() -> RuntimeOperationLeaseLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        do {
            let data = try Data(contentsOf: url)
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
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: data) else {
            if case .loaded(let existing) = loadResult() {
                throw RuntimeOperationLeaseRepositoryError.existingOperation(
                    operationId: existing.operationId,
                    operation: existing.operation.rawValue
                )
            }
            throw RuntimeOperationLeaseRepositoryError.createFailed(url.path)
        }
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
            try FileManager.default.removeItem(at: url)
        case .failed(let reason):
            throw RuntimeOperationLeaseRepositoryError.readFailed(reason)
        }
    }
}
