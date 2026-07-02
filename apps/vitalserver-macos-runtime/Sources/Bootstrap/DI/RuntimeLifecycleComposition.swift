import Application
import Foundation
import Contracts
import OutboundAdapters
import InboundAdapters
import Errors
import RuntimeControl

public struct RuntimeLifecycleComposition {
    public let httpProber: RuntimeHTTPProber
    public let serviceManager: RuntimeServiceManager
    public let statusReporter: RuntimeStatusReporter
    public let healthChecker: RuntimeHealthChecker
    public let serviceController: RuntimeServiceController
    public let guestBootstrapResultReader: any RuntimeGuestBootstrapResultReader

    public static func resolve(
        paths: LauncherPaths,
        clock: RuntimeClock,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber?,
        serviceManager: RuntimeServiceManager?,
        runtimeStatusRepository: RuntimeStatusRepository?,
        guestBootstrapResultReader: (any RuntimeGuestBootstrapResultReader)?,
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
        let statusDocumentUseCase = BuildRuntimeStatusDocumentUseCase()
        let statusReporter = RuntimeStatusReporter(
            repository: runtimeStatusRepository ?? JSONFileRuntimeStatusRepository(
                url: installedPaths.runtimeStatus,
                requiredExistingRoot: installedPaths.productRoot
            ),
            productIdentifier: Constants.Product.identifier,
            productRoot: installedPaths.productRoot,
            runtimeHome: installedPaths.runtimeHome,
            makeStatusDocument: statusDocumentUseCase.build,
            makeProgressDocument: statusDocumentUseCase.progressUpdate
        )
        let defaultGuestDocumentReader = makeGuestDocumentReader(installedPaths: installedPaths)
        let resolvedGuestBootstrapResultReader = guestBootstrapResultReader ?? defaultGuestDocumentReader
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
            guestBootstrapResultReader: resolvedGuestBootstrapResultReader,
            guestControlGatewayForBaseURL: { baseURL in
                try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL,
                    timeout: RuntimeLifecycleComposition.guestControlAPIStatusReadTimeoutSeconds
                )
            }
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
            guestBootstrapResultReader: resolvedGuestBootstrapResultReader
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
            watchdogManagedOperationGraceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            proxyHealthURL: { Constants.Runtime.proxyHealthURL(port: $0) },
            redisUIHealthURL: { Constants.Runtime.redisUIHealthURL(port: $0) },
            swaggerUIHealthURL: { Constants.Runtime.swaggerUIHealthURL(port: $0) }
        )
    }

    private static func makeGuestDocumentReader(installedPaths: InstalledRuntimePaths) -> JSONFileRuntimeGuestDocumentReader {
        let guestRunDirectory = installedPaths.guestRunDirectory
        return JSONFileRuntimeGuestDocumentReader(
            bootstrapResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.bootstrapResultFile)
        )
    }
}

private extension RuntimeLifecycleComposition {
    static let guestControlAPIStatusReadTimeoutSeconds: TimeInterval = 1
}
