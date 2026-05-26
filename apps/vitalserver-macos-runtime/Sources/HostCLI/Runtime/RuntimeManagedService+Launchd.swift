import Core
import Contracts

extension RuntimeManagedService {
    var launchDaemonPlist: String {
        "\(Constants.InstallPaths.launchDaemons)/\(label).plist"
    }

    var displayName: String {
        switch self {
        case .vm:
            "VM"
        case .proxy:
            "proxy"
        case .guestLogSync:
            "guest log sync"
        case .watchdog:
            "watchdog"
        }
    }
}
