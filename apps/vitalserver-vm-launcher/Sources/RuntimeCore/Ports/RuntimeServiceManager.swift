public protocol RuntimeServiceManager {
    func state(label: String) -> String
    func start(label: String, plist: String)
    func restart(label: String)
    func stop(label: String)
    func setEnabled(label: String, enabled: Bool) -> RuntimeProcessResult
}
