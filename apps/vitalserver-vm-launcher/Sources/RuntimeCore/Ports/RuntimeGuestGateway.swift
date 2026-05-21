import Foundation

public protocol RuntimeGuestGateway {
    func loadRuntimeState() -> GuestRuntimeStateDocument?
    func loadBootstrapResult() -> GuestBootstrapResultDocument?
    func removeUpdateActivationResult() throws
    func writeUpdateActivationRequest(requestId: String, requestedAt: String, version: String) throws
    func loadUpdateActivationResult() -> GuestUpdateActivationResultDocument?
    func removeDatastoreRepairResult() throws
    func writeDatastoreRepairRequest(requestId: String, requestedAt: String) throws
    func loadDatastoreRepairResult() -> DatastoreRepairResultDocument?
}
