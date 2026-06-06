import Contracts
import Foundation
import Errors

public typealias RuntimeGuestDocumentLoadResult<Document> = Contracts.RuntimeGuestDocumentLoadResult<Document>

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
