import Contracts
import Errors
public protocol RuntimeServiceManager {
    func state(service: RuntimeManagedService) -> RuntimeServiceState
    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult
    func restart(service: RuntimeManagedService) -> RuntimeProcessResult
    func stop(service: RuntimeManagedService) -> RuntimeProcessResult
    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult
}
