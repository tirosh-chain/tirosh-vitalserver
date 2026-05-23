import Foundation
import RuntimeControl
import RuntimeCore

public struct RuntimePaths {
    public let launcher: String
    public let uninstaller: String
    public let vmIPFile: String
    public let runtimeState: String
    public let runtimeStatus: String
    public let proxyLaunchDaemon: String

    public init(
        launcher: String = RuntimeAdapterConstants.Paths.launcher,
        uninstaller: String = RuntimeAdapterConstants.Paths.uninstaller,
        vmIPFile: String = RuntimeAdapterConstants.Paths.vmIPFile,
        runtimeState: String = RuntimeAdapterConstants.Paths.runtimeState,
        runtimeStatus: String = RuntimeAdapterConstants.Paths.runtimeStatus,
        proxyLaunchDaemon: String = RuntimeAdapterConstants.Paths.proxyLaunchDaemon
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.vmIPFile = vmIPFile
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.proxyLaunchDaemon = proxyLaunchDaemon
    }
}
