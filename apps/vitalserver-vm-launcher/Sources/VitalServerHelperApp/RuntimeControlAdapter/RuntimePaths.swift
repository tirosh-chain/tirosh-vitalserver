import Foundation
import RuntimeCore

struct RuntimePaths {
    let launcher: String
    let uninstaller: String
    let vmIPFile: String
    let runtimeState: String
    let runtimeStatus: String
    let proxyLaunchDaemon: String

    init(
        launcher: String = AppConstants.Paths.launcher,
        uninstaller: String = AppConstants.Paths.uninstaller,
        vmIPFile: String = AppConstants.Paths.vmIPFile,
        runtimeState: String = AppConstants.Paths.runtimeState,
        runtimeStatus: String = AppConstants.Paths.runtimeStatus,
        proxyLaunchDaemon: String = AppConstants.Paths.proxyLaunchDaemon
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.vmIPFile = vmIPFile
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.proxyLaunchDaemon = proxyLaunchDaemon
    }
}
