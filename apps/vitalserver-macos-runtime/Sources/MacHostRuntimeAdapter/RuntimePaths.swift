import Foundation
import RuntimeControl
import Core
import Contracts

struct RuntimePaths {
    let launcher: String
    let uninstaller: String
    let vmIPFile: String
    let runtimeState: String
    let runtimeStatus: String
    let runtimeEvents: String
    let proxyLaunchDaemon: String

    init(
        launcher: String = RuntimeAdapterConstants.Paths.launcher,
        uninstaller: String = RuntimeAdapterConstants.Paths.uninstaller,
        vmIPFile: String = RuntimeAdapterConstants.Paths.vmIPFile,
        runtimeState: String = RuntimeAdapterConstants.Paths.runtimeState,
        runtimeStatus: String = RuntimeAdapterConstants.Paths.runtimeStatus,
        runtimeEvents: String = RuntimeAdapterConstants.Paths.runtimeEvents,
        proxyLaunchDaemon: String = RuntimeAdapterConstants.Paths.proxyLaunchDaemon
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.vmIPFile = vmIPFile
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.runtimeEvents = runtimeEvents
        self.proxyLaunchDaemon = proxyLaunchDaemon
    }
}
