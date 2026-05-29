import Foundation
import RuntimeControl
import Core
import Contracts

struct RuntimePaths {
    let launcher: String
    let uninstaller: String
    let runtimeState: String
    let runtimeStatus: String
    let runtimeEvents: String
    let runtimeObservabilityDB: String
    let proxyLaunchDaemon: String

    init(
        launcher: String = RuntimeAdapterConstants.Paths.launcher,
        uninstaller: String = RuntimeAdapterConstants.Paths.uninstaller,
        runtimeState: String = RuntimeAdapterConstants.Paths.runtimeState,
        runtimeStatus: String = RuntimeAdapterConstants.Paths.runtimeStatus,
        runtimeEvents: String = RuntimeAdapterConstants.Paths.runtimeEvents,
        runtimeObservabilityDB: String = RuntimeAdapterConstants.Paths.runtimeObservabilityDB,
        proxyLaunchDaemon: String = RuntimeAdapterConstants.Paths.proxyLaunchDaemon
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.runtimeEvents = runtimeEvents
        self.runtimeObservabilityDB = runtimeObservabilityDB
        self.proxyLaunchDaemon = proxyLaunchDaemon
    }
}
