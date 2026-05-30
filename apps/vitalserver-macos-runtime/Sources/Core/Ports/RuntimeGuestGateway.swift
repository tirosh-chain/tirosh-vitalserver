import Contracts
import Foundation

public enum RuntimeGuestDocumentLoadResult<Document> {
    case missing
    case loaded(Document)
    case failed(String)
}

public protocol RuntimeGuestGateway {
    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>
    func removeUpdateActivationResult() throws
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>
    func removeUpdateShutdownResult() throws
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    func removeDatastoreRepairResult() throws
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
}
