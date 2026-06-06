import Application
import Foundation
import Contracts
import OutboundAdapters
import InboundAdapters
import Errors

public struct RuntimeLifecycleComposition {
    public let httpProber: RuntimeHTTPProber
    public let serviceManager: RuntimeServiceManager
    public let statusReporter: RuntimeStatusReporter
    public let healthChecker: RuntimeHealthChecker
    public let serviceController: RuntimeServiceController
    public let guestGateway: RuntimeGuestGateway

    public static func resolve(
        paths: LauncherPaths,
        clock: RuntimeClock,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber?,
        serviceManager: RuntimeServiceManager?,
        runtimeStatusRepository: RuntimeStatusRepository?,
        guestGateway: RuntimeGuestGateway?,
        fileStore: RuntimeFileStore,
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String,
        launchctlPath: String,
        prepareServiceForStop: @escaping (RuntimeManagedService) throws -> Void,
        waitForVMProcessStoppedAfterServiceUnload: @escaping () throws -> Void,
        waitForVMProcessExitAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        log: @escaping (String) -> Void
    ) -> RuntimeLifecycleComposition {
        let installedPaths = paths.installed
        let resolvedHTTPProber = httpProber ?? CurlRuntimeHTTPProber(commandRunner: commandRunner)
        let resolvedServiceManager = serviceManager ?? LaunchdRuntimeServiceManager(commandRunner: commandRunner)
        let statusReporter = RuntimeStatusReporter(
            repository: runtimeStatusRepository ?? JSONFileRuntimeStatusRepository(url: installedPaths.runtimeStatus),
            productIdentifier: Constants.Product.identifier,
            productRoot: installedPaths.productRoot,
            runtimeHome: installedPaths.runtimeHome
        )
        let resolvedGuestGateway = guestGateway ?? makeGuestGateway(installedPaths: installedPaths)
        let healthChecker = RuntimeHealthChecker(
            context: healthCheckerContext(
                installedPaths: installedPaths,
                plistBuddyPath: plistBuddyPath,
                lsofPath: lsofPath,
                curlPath: curlPath
            ),
            fileStore: fileStore,
            serviceManager: resolvedServiceManager,
            commandRunner: commandRunner,
            httpProber: resolvedHTTPProber,
            guestGateway: resolvedGuestGateway
        )
        let serviceStopWaiter = RuntimeServiceStopWaiter(
            serviceState: { service in
                healthChecker.launchdState(service)
            },
            now: { clock.now },
            waitForVMProcessStoppedAfterServiceUnload: waitForVMProcessStoppedAfterServiceUnload,
            vmStopTimeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            serviceStopTimeoutSeconds: Constants.Runtime.serviceStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds
        )
        let serviceController = RuntimeServiceController(
            serviceManager: resolvedServiceManager,
            serviceState: { service in
                healthChecker.launchdState(service)
            },
            prepareForStop: prepareServiceForStop,
            waitUntilStopped: { service in
                try serviceStopWaiter.waitUntilStopped(service)
            },
            waitForVMProcessExitAfterGuestPoweroff: waitForVMProcessExitAfterGuestPoweroff,
            launchDaemonPlist: RuntimeManagedServicePaths.launchDaemonPlist,
            launchctlPath: launchctlPath,
            log: log
        )

        return RuntimeLifecycleComposition(
            httpProber: resolvedHTTPProber,
            serviceManager: resolvedServiceManager,
            statusReporter: statusReporter,
            healthChecker: healthChecker,
            serviceController: serviceController,
            guestGateway: resolvedGuestGateway
        )
    }

    private static func healthCheckerContext(
        installedPaths: InstalledRuntimePaths,
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String
    ) -> RuntimeHealthCheckerContext {
        RuntimeHealthCheckerContext(
            installedPaths: installedPaths,
            vmExecutablePath: Constants.InstallPaths.vmBin,
            proxyExecutablePath: Constants.InstallPaths.proxyRun,
            rootfsBaseURL: installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
            vmDiskURL: installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
            plistBuddyPath: plistBuddyPath,
            lsofPath: lsofPath,
            curlPath: curlPath,
            proxyLaunchDaemonPlist: RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
            defaultProxyPort: Constants.Guest.publicPort,
            runtimeStateStaleAfterSeconds: Constants.Runtime.runtimeStateStaleAfterSeconds,
            watchdogManagedOperationGraceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            proxyHealthURL: { Constants.Runtime.proxyHealthURL(port: $0) },
            redisUIHealthURL: { Constants.Runtime.redisUIHealthURL(port: $0) },
            swaggerUIHealthURL: { Constants.Runtime.swaggerUIHealthURL(port: $0) },
            auditProxyStatusURL: { Constants.Runtime.auditProxyStatusURL(port: $0) }
        )
    }

    private static func makeGuestGateway(installedPaths: InstalledRuntimePaths) -> RuntimeGuestGateway {
        let guestRunDirectory = installedPaths.guestRunDirectory
        return JSONFileRuntimeGuestGateway(
            runtimeStateURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.runtimeStateFile),
            bootstrapResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.bootstrapResultFile),
            updateActivationRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateActivationRequestFile),
            updateActivationResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateActivationResultFile),
            updateShutdownRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateShutdownRequestFile),
            updateShutdownResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateShutdownResultFile),
            datastoreRepairRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairRequestFile),
            datastoreRepairResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairResultFile)
        )
    }
}
