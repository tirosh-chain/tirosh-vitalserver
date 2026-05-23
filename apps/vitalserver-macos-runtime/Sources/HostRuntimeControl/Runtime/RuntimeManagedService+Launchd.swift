import RuntimeCore
import RuntimeContracts

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
        case .watchdog:
            "watchdog"
        }
    }
}
