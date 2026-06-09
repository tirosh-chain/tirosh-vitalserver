import Contracts
import Foundation

public enum RuntimeOperationLeaseLoadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeOperationLeaseDocument)
    case failed(String)
}

public protocol RuntimeOperationLeaseRepository {
    func loadResult() -> RuntimeOperationLeaseLoadResult
    func acquire(_ document: RuntimeOperationLeaseDocument) throws
    func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws
    func release(operationId: String) throws
}
