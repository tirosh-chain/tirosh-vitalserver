import Contracts
import Foundation

public protocol RuntimeStatusRepository {
    func load() -> RuntimeStatusDocument?
    func save(_ document: RuntimeStatusDocument) throws
}
