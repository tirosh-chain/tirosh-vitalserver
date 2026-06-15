import Bootstrap
import Contracts
import Errors

extension RuntimeManagedService {
    var launchDaemonPlist: String {
        RuntimeManagedServicePaths.launchDaemonPlist(self)
    }

    var displayName: String {
        RuntimeManagedServicePaths.displayName(self)
    }
}
