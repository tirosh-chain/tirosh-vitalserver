public enum RuntimeManagedService: CaseIterable, Equatable, Sendable {
    case updateHandoffSupervisor
    case platformAgent
    case vm
    case proxy
    case guestLogSync
    case sleepPrevention
    case watchdog

    public static let startOrder: [RuntimeManagedService] = [
        .platformAgent,
        .vm,
        .guestLogSync,
        .watchdog,
        .proxy,
    ]
    public static let stopOrder: [RuntimeManagedService] = [.watchdog, .guestLogSync, .proxy, .vm, .sleepPrevention]
    public static let uninstallOrder: [RuntimeManagedService] =
        stopOrder + [.platformAgent, .updateHandoffSupervisor]

    public var label: String {
        switch self {
        case .updateHandoffSupervisor:
            "ai.tirosh.vitalserver.helper.update-handoff-supervisor"
        case .platformAgent:
            "ai.tirosh.vitalserver.helper.platform-agent"
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

    public var runtimeServiceDisplayName: String {
        switch self {
        case .updateHandoffSupervisor:
            "update handoff supervisor"
        case .platformAgent:
            "Platform Agent"
        case .vm:
            "VM"
        case .proxy:
            "proxy"
        case .guestLogSync:
            "guest log sync"
        case .sleepPrevention:
            "sleep prevention"
        case .watchdog:
            "watchdog"
        }
    }
}
