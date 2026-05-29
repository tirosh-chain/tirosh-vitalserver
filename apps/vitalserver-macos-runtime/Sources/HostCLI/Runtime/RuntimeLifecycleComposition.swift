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
            isLoaded: { service in
                healthChecker.isLaunchdLoaded(service)
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

        let launchdOutputLog = paths.installed.centralRuntimeLogsDirectory.appendingPathComponent("launchd.out.log")
        let logWatermark = runtimeLogWatermark(launchdOutputLog, fileStore: fileStore)
        log("requesting graceful VM process stop before launchd unload", clock: clock)
        do {
            try ProcessState.requestStopAndWait(
                pidFile: paths.pidFile,
                fileStore: fileStore,
                timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
                pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
                log: { message in log(message, clock: clock) }
            )
        } catch {
            guard isVMStopTimeout(error) else {
                throw error
            }
            try forceStopAfterDiskSafeShutdown(
                originalError: error,
                pidFile: paths.pidFile,
                launchdOutputLog: launchdOutputLog,
                logWatermark: logWatermark,
                fileStore: fileStore,
                clock: clock
            )
        }
        log("VM process stopped before launchd unload", clock: clock)
    }

    private static func forceStopAfterDiskSafeShutdown(
        originalError: Error,
        pidFile: URL,
        launchdOutputLog: URL,
        logWatermark: UInt64,
        fileStore: RuntimeFileStore,
        clock: RuntimeClock
    ) throws {
        log("VM graceful stop timed out; waiting for guest disk-safe shutdown marker", clock: clock)
        guard waitForGuestDiskSafeShutdown(
            launchdOutputLog: launchdOutputLog,
            logWatermark: logWatermark,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmDiskSafeShutdownWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds
        ) else {
            throw originalError
        }

        log("guest disk-safe shutdown marker observed; force stopping VM process", clock: clock)
        try ProcessState.forceKillAndWait(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmForceStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            log: { message in log(message, clock: clock) }
        )
    }

    private static func runtimeLogWatermark(_ logURL: URL, fileStore: RuntimeFileReading) -> UInt64 {
        (try? fileStore.fileSize(logURL)) ?? 0
    }

    private static func waitForGuestDiskSafeShutdown(
        launchdOutputLog: URL,
        logWatermark: UInt64,
        fileStore: RuntimeFileReading,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            if guestDiskSafeShutdownReached(
                launchdOutputLog: launchdOutputLog,
                logWatermark: logWatermark,
                fileStore: fileStore
            ) {
                return true
            }
            guard Date() < deadline else {
                return false
            }
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
    }

    private static func guestDiskSafeShutdownReached(
        launchdOutputLog: URL,
        logWatermark: UInt64,
        fileStore: RuntimeFileReading
    ) -> Bool {
        guard let data = try? fileStore.readData(launchdOutputLog) else {
            return false
        }
        return RuntimeVMShutdownLogProbe.diskSafeShutdownReached(in: data, after: logWatermark)
    }

    private static func isVMStopTimeout(_ error: Error) -> Bool {
        guard case let LauncherError.runtimeOperationFailed(message) = error else {
            return false
        }
        return message.contains("VM process did not stop within")
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
        while healthChecker.isLaunchdLoaded(service) {
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
            datastoreRepairRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairRequestFile),
            datastoreRepairResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairResultFile)
        )
    }
}
