import Contracts
import Foundation
import Errors

public protocol RuntimeStatusRepository {
    func loadResult() -> RuntimeStatusDocumentLoadResult
    func save(_ document: RuntimeStatusDocument) throws
}
