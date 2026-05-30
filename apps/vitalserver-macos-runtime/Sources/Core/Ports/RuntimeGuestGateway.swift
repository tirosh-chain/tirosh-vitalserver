import Contracts
import Foundation

public enum RuntimeGuestDocumentLoadResult<Document> {
    case missing
    case loaded(Document)
    case failed(String)

    public var document: Document? {
        guard case .loaded(let document) = self else {
            return nil
        }
        return document
    }
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

public extension RuntimeGuestGateway {
    func loadRuntimeState() -> GuestRuntimeStateDocument? {
        loadRuntimeStateDocument().document
    }

    func loadBootstrapResult() -> GuestBootstrapResultDocument? {
        loadBootstrapResultDocument().document
    }

    func loadUpdateActivationResult() -> GuestUpdateActivationResultDocument? {
        loadUpdateActivationResultDocument().document
    }

    func loadUpdateShutdownResult() -> GuestUpdateShutdownResultDocument? {
        loadUpdateShutdownResultDocument().document
    }

    func loadDatastoreRepairResult() -> DatastoreRepairResultDocument? {
        loadDatastoreRepairResultDocument().document
    }
}
