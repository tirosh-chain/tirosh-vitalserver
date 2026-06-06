import Contracts
import Foundation
import Errors

public enum RuntimeStatusDocumentLoadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeStatusDocument)
    case failed(String)
}

public protocol RuntimeStatusRepository {
    func loadResult() -> RuntimeStatusDocumentLoadResult
    func save(_ document: RuntimeStatusDocument) throws
}
