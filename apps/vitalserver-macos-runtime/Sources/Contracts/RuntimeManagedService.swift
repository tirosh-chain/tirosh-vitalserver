public enum RuntimeManagedService: CaseIterable, Equatable, Sendable {
    case vm
    case proxy
    case guestLogSync
    case sleepPrevention
    case watchdog

    public static let startOrder: [RuntimeManagedService] = [.vm, .proxy, .guestLogSync, .watchdog]
    public static let stopOrder: [RuntimeManagedService] = [.watchdog, .guestLogSync, .proxy, .vm, .sleepPrevention]

    public var label: String {
        switch self {
        case .vm:
            "com.tirosh.vitalserver-vm"
        case .proxy:
            "com.tirosh.vitalserver-proxy"
        case .guestLogSync:
            "com.tirosh.vitalserver-guest-log-sync"
        case .sleepPrevention:
            "com.tirosh.vitalserver-sleep-prevention"
        case .watchdog:
            "com.tirosh.vitalserver-watchdog"
        }
    }
}
