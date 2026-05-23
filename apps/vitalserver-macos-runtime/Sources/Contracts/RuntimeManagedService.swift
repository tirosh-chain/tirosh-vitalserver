public enum RuntimeManagedService: CaseIterable, Equatable, Sendable {
    case vm
    case proxy
    case watchdog

    public static let startOrder: [RuntimeManagedService] = [.vm, .proxy, .watchdog]
    public static let stopOrder: [RuntimeManagedService] = [.watchdog, .proxy, .vm]

    public var label: String {
        switch self {
        case .vm:
            "com.tirosh.vitalserver-vm"
        case .proxy:
            "com.tirosh.vitalserver-proxy"
        case .watchdog:
            "com.tirosh.vitalserver-watchdog"
        }
    }
}
