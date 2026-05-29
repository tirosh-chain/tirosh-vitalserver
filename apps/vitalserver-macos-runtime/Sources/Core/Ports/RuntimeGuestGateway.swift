import Contracts
import Foundation

public protocol RuntimeGuestGateway {
    func loadRuntimeState() -> GuestRuntimeStateDocument?
    func loadBootstrapResult() -> GuestBootstrapResultDocument?
    func removeUpdateActivationResult() throws
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws
    func loadUpdateActivationResult() -> GuestUpdateActivationResultDocument?
    func removeUpdateShutdownResult() throws
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws
    func loadUpdateShutdownResult() -> GuestUpdateShutdownResultDocument?
    func removeDatastoreRepairResult() throws
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws
    func loadDatastoreRepairResult() -> DatastoreRepairResultDocument?
}
