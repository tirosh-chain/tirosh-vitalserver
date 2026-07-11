import Contracts
import Errors

public enum RuntimeManagedServicePaths {
    public static func launchDaemonPlist(_ service: RuntimeManagedService) -> String {
        "\(Constants.InstallPaths.launchDaemons)/\(service.label).plist"
    }

    public static func displayName(_ service: RuntimeManagedService) -> String {
        switch service {
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
