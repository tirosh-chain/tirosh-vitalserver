public protocol RuntimeServiceManager {
    func state(service: RuntimeManagedService) -> RuntimeServiceState
    func start(service: RuntimeManagedService, plist: String)
    func restart(service: RuntimeManagedService)
    func stop(service: RuntimeManagedService)
    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult
}
