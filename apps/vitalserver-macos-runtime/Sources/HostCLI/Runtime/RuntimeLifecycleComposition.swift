import Foundation
import HostInfrastructure
import Core
import Contracts

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
            serviceState: { service in
                healthChecker.launchdState(service)
            },
            prepareForStop: { service in
                try prepareServiceForStop(
                    service,
                    paths: paths,
                    fileStore: fileStore,
                    clock: clock
                )
            },
            waitUntilStopped: { service in
                try waitUntilServiceStops(
                    service,
                    paths: paths,
                    healthChecker: healthChecker,
                    fileStore: fileStore,
                    clock: clock
                )
            },
            waitForVMProcessExitAfterGuestPoweroff: {
                try waitForVMProcessExitAfterGuestPoweroff(
                    paths: paths,
                    fileStore: fileStore,
                    clock: clock
                )
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

    private static func prepareServiceForStop(
        _ service: RuntimeManagedService,
        paths: LauncherPaths,
        fileStore: RuntimeFileStore,
        clock: RuntimeClock
    ) throws {
        guard service == .vm else {
            return
        }

        log("requesting graceful VM process stop before launchd unload", clock: clock)
        try ProcessState.requestStopAndWait(
            pidFile: paths.pidFile,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            log: { message in log(message, clock: clock) }
        )
        log("VM process stopped before launchd unload", clock: clock)
        do {
            try RuntimeVMLifecycleStore(
                url: paths.installed.vmLifecycle,
                fileStore: fileStore
            ).write(state: .stopped, message: "VM process stopped before launchd unload")
        } catch {
            log("failed to write VM lifecycle stopped state after process stop error=\(error)", clock: clock)
        }
    }

    private static func waitForVMProcessExitAfterGuestPoweroff(
        paths: LauncherPaths,
        fileStore: RuntimeFileStore,
        clock: RuntimeClock
    ) throws {
        log("waiting for VM process to exit after guest poweroff request", clock: clock)
        try ProcessState.waitUntilStopped(
            pidFile: paths.pidFile,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            log: { message in log(message, clock: clock) }
        )
        log("VM process exited after guest poweroff request", clock: clock)
    }

    private static func waitUntilServiceStops(
        _ service: RuntimeManagedService,
        paths: LauncherPaths,
        healthChecker: RuntimeHealthChecker,
        fileStore: RuntimeFileStore,
        clock: RuntimeClock
    ) throws {
        let timeout = service == .vm
            ? Constants.Runtime.vmStopWaitTimeoutSeconds
            : Constants.Runtime.serviceStopWaitTimeoutSeconds
        let deadline = clock.now.addingTimeInterval(timeout)
        while try launchdServiceIsLoaded(service, healthChecker: healthChecker) {
            guard clock.now < deadline else {
                throw LauncherError.runtimeOperationFailed(
                    "service did not unload within \(Int(timeout))s label=\(service.label)"
                )
            }
            Thread.sleep(forTimeInterval: Constants.Runtime.serviceStopPollIntervalSeconds)
        }

        guard service == .vm else {
            return
        }
        try ProcessState.waitUntilStopped(
            pidFile: paths.pidFile,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds
        )
    }

    private static func launchdServiceIsLoaded(
        _ service: RuntimeManagedService,
        healthChecker: RuntimeHealthChecker
    ) throws -> Bool {
        let state = healthChecker.launchdState(service)
        switch state {
        case .loaded:
            return true
        case .notLoaded:
            return false
        case .readFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "launchd service state read failed label=\(service.label) reason=\(reason)"
            )
        case .permissionDenied(let reason):
            throw LauncherError.runtimeOperationFailed(
                "launchd service state permission denied label=\(service.label) reason=\(reason)"
            )
        case .unknown(let value):
            throw LauncherError.runtimeOperationFailed(
                "launchd service state unknown label=\(service.label) value=\(value)"
            )
        }
    }

    private static func log(_ message: String, clock: RuntimeClock) {
        print("[\(ISO8601DateFormatter().string(from: clock.now))] \(message)")
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
