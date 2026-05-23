public protocol RuntimeServiceManager {
    func state(service: RuntimeManagedService) -> String
    func start(service: RuntimeManagedService, plist: String)
    func restart(service: RuntimeManagedService)
    func stop(service: RuntimeManagedService)
    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult
}
