import Application
import Contracts
import Foundation
import InboundAdapters
import OutboundAdapters

public struct RuntimeApplicationContainer {
    public let paths: LauncherPaths
    public let installedPaths: InstalledRuntimePaths
    public let clock: RuntimeClock
    public let sleeper: RuntimeSleeper
    public let commandRunner: RuntimeCommandRunner
    public let httpProber: RuntimeHTTPProber
    public let serviceManager: RuntimeServiceManager
    public let statusReporter: RuntimeStatusReporter
    public let healthChecker: RuntimeHealthChecker
    public let serviceController: RuntimeServiceController
    public let guestGateway: RuntimeGuestGateway
    public let fileStore: RuntimeFileStore

    public init(
        paths: LauncherPaths,
        clock: RuntimeClock = SystemRuntimeClock(),
        sleeper: RuntimeSleeper = ThreadRuntimeSleeper(),
        commandRunner: RuntimeCommandRunner = SystemRuntimeCommandRunner(),
        httpProber: RuntimeHTTPProber? = nil,
        serviceManager: RuntimeServiceManager? = nil,
        runtimeStatusRepository: RuntimeStatusRepository? = nil,
        guestGateway: RuntimeGuestGateway? = nil,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String,
        launchctlPath: String,
        prepareServiceForStop: @escaping (RuntimeManagedService) throws -> Void,
        waitForVMProcessStoppedAfterServiceUnload: @escaping () throws -> Void,
        waitForVMProcessExitAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        let composition = RuntimeLifecycleComposition.resolve(
            paths: paths,
            clock: clock,
            commandRunner: commandRunner,
            httpProber: httpProber,
            serviceManager: serviceManager,
            runtimeStatusRepository: runtimeStatusRepository,
            guestGateway: guestGateway,
            fileStore: fileStore,
            plistBuddyPath: plistBuddyPath,
            lsofPath: lsofPath,
            curlPath: curlPath,
            launchctlPath: launchctlPath,
            prepareServiceForStop: prepareServiceForStop,
            waitForVMProcessStoppedAfterServiceUnload: waitForVMProcessStoppedAfterServiceUnload,
            waitForVMProcessExitAfterGuestPoweroff: waitForVMProcessExitAfterGuestPoweroff,
            log: log
        )
        self.paths = paths
        self.installedPaths = paths.installed
        self.clock = clock
        self.sleeper = sleeper
        self.commandRunner = commandRunner
        self.httpProber = composition.httpProber
        self.serviceManager = composition.serviceManager
        self.statusReporter = composition.statusReporter
        self.healthChecker = composition.healthChecker
        self.serviceController = composition.serviceController
        self.guestGateway = composition.guestGateway
        self.fileStore = fileStore
    }
}
