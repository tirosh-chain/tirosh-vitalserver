import RuntimeContracts
import Foundation

public protocol RuntimeGuestGateway {
    func loadRuntimeState() -> GuestRuntimeStateDocument?
    func loadBootstrapResult() -> GuestBootstrapResultDocument?
    func removeUpdateActivationResult() throws
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws
    func loadUpdateActivationResult() -> GuestUpdateActivationResultDocument?
    func removeDatastoreRepairResult() throws
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws
    func loadDatastoreRepairResult() -> DatastoreRepairResultDocument?
}
