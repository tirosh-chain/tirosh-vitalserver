import Bootstrap
import Contracts

extension RuntimeManagedService {
    var launchDaemonPlist: String {
        RuntimeManagedServicePaths.launchDaemonPlist(self)
    }

    var displayName: String {
        RuntimeManagedServicePaths.displayName(self)
    }
}
