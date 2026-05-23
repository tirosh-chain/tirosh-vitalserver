import Foundation
import HostRuntimeInfrastructure
import RuntimeCore
import RuntimeContracts

struct RuntimeLifecycleComposition {
    let httpProber: RuntimeHTTPProber
    let serviceManager: RuntimeServiceManager
    let statusReporter: RuntimeStatusReporter
    let healthChecker: RuntimeHealthChecker
    let serviceController: RuntimeServiceController
    let guestGateway: RuntimeGuestGateway

    static func resolve(
        paths: LauncherPaths,
        clock: RuntimeClock,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber?,
        serviceManager: RuntimeServiceManager?,
        runtimeStatusRepository: RuntimeStatusRepository?,
        guestGateway: RuntimeGuestGateway?,
        fileStore: RuntimeFileStore
    ) -> RuntimeLifecycleComposition {
        let installedPaths = paths.installed
        let resolvedHTTPProber = httpProber ?? CurlRuntimeHTTPProber(commandRunner: commandRunner)
        let resolvedServiceManager = serviceManager ?? LaunchdRuntimeServiceManager(commandRunner: commandRunner)
        let statusReporter = RuntimeStatusReporter(
            repository: runtimeStatusRepository ?? JSONFileRuntimeStatusRepository(url: installedPaths.runtimeStatus),
            productRoot: installedPaths.productRoot,
            runtimeHome: installedPaths.runtimeHome
        )
        let resolvedGuestGateway = guestGateway ?? makeGuestGateway(installedPaths: installedPaths)
        let healthChecker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: resolvedServiceManager,
            commandRunner: commandRunner,
            httpProber: resolvedHTTPProber,
            guestGateway: resolvedGuestGateway
        )
        let serviceController = RuntimeServiceController(
            serviceManager: resolvedServiceManager,
            isLoaded: { service in
                healthChecker.isLaunchdLoaded(service)
            },
            log: { message in
                print("[\(ISO8601DateFormatter().string(from: clock.now))] \(message)")
            }
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

    private static func makeGuestGateway(installedPaths: InstalledRuntimePaths) -> RuntimeGuestGateway {
        let guestRunDirectory = installedPaths.guestRunDirectory
        return JSONFileRuntimeGuestGateway(
            runtimeStateURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.runtimeStateFile),
            bootstrapResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.bootstrapResultFile),
            updateActivationRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateActivationRequestFile),
            updateActivationResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateActivationResultFile),
            datastoreRepairRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairRequestFile),
            datastoreRepairResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairResultFile)
        )
    }
}
