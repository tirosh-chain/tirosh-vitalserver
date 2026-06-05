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
            "ai.tirosh.vitalserver.helper.vm"
        case .proxy:
            "ai.tirosh.vitalserver.helper.proxy"
        case .guestLogSync:
            "ai.tirosh.vitalserver.helper.guest-log-sync"
        case .sleepPrevention:
            "ai.tirosh.vitalserver.helper.sleep-prevention"
        case .watchdog:
            "ai.tirosh.vitalserver.helper.watchdog"
        }
    }
}
