import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Errors
import Workflow

struct RuntimeLifecycle {
    let container: RuntimeApplicationContainer
    let paths: LauncherPaths
    let installedPaths: InstalledRuntimePaths
    let clock: RuntimeClock
    let sleeper: RuntimeSleeper
    let commandRunner: RuntimeCommandRunner
    let httpProber: RuntimeHTTPProber
    let statusReporter: RuntimeStatusReporter
    let healthChecker: RuntimeHealthChecker
    let serviceController: RuntimeServiceController
    let guestGateway: RuntimeGuestGateway
    let fileStore: RuntimeFileStore

    init(
        paths: LauncherPaths,
        clock: RuntimeClock = SystemRuntimeClock(),
        sleeper: RuntimeSleeper = ThreadRuntimeSleeper(),
        commandRunner: RuntimeCommandRunner = SystemRuntimeCommandRunner(),
        httpProber: RuntimeHTTPProber? = nil,
        serviceManager: RuntimeServiceManager? = nil,
        runtimeStatusRepository: RuntimeStatusRepository? = nil,
        guestGateway: RuntimeGuestGateway? = nil,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) {
        let lifecycleLog: (String) -> Void = { message in
            print("[\(ISO8601DateFormatter().string(from: clock.now))] \(message)")
        }
        let container = RuntimeApplicationContainer(
            paths: paths,
            clock: clock,
            sleeper: sleeper,
            commandRunner: commandRunner,
            httpProber: httpProber,
            serviceManager: serviceManager,
            runtimeStatusRepository: runtimeStatusRepository,
            guestGateway: guestGateway,
            fileStore: fileStore,
            plistBuddyPath: Constants.Commands.plistBuddy,
            lsofPath: Constants.Commands.lsof,
            curlPath: Constants.Commands.curl,
            launchctlPath: Constants.Commands.launchctl,
            prepareServiceForStop: { service in
                try RuntimeLifecycle.prepareServiceForStop(
                    service,
                    paths: paths,
                    fileStore: fileStore,
                    log: lifecycleLog
                )
            },
            waitForVMProcessStoppedAfterServiceUnload: {
                try StopRuntimeVMProcessUseCase().waitUntilStopped(
                    timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
                    pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
                    allowMissingPidFile: true,
                    operations: ProcessState.stopOperations(
                        pidFile: paths.pidFile,
                        fileStore: fileStore,
                        log: lifecycleLog
                    )
                )
            },
            waitForVMProcessExitAfterGuestPoweroff: { expectedVMProcessID in
                try RuntimeLifecycle.waitForVMProcessExitAfterGuestPoweroff(
                    expectedVMProcessID: expectedVMProcessID,
                    paths: paths,
                    fileStore: fileStore,
                    log: lifecycleLog
                )
            },
            log: lifecycleLog
        )
        self.container = container
        self.paths = container.paths
        self.installedPaths = container.installedPaths
        self.clock = container.clock
        self.sleeper = container.sleeper
        self.commandRunner = container.commandRunner
        self.httpProber = container.httpProber
        self.fileStore = container.fileStore
        self.statusReporter = container.statusReporter
        self.guestGateway = container.guestGateway
        self.healthChecker = container.healthChecker
        self.serviceController = container.serviceController
    }

    var productRoot: URL {
        installedPaths.productRoot
    }

    var bundlesDirectory: URL {
        installedPaths.bundlesDirectory
    }

    var backupsDirectory: URL {
        installedPaths.backupsDirectory
    }

    var logsDirectory: URL {
        installedPaths.centralRuntimeLogsDirectory
    }

    var runtimeStatus: URL {
        installedPaths.runtimeStatus
    }

    var rootfsBase: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    var vmDisk: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
    }

    var runtimeVersion: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion)
    }

    var guestRunDirectory: URL {
        installedPaths.guestRunDirectory
    }

    func run(arguments: [String]) throws {
        switch try RuntimeLifecycleCommand.parse(arguments) {
        case .install:
            try install()
        case .installProvision:
            try installProvision()
        case .preinstallCheck:
            try preinstallCheck()
        case .status:
            printStatus()
        case .health:
            try health()
        case .guestLogSync:
            guestLogSync()
        case .watchdog:
            try watchdog()
        case .configure(let command):
            try configure(command)
        case .verifyBundle(let bundleURL):
            try verifyBundle(bundleURL)
        case .stageBundle(let bundleURL):
            _ = try stageBundle(bundleURL)
        case .applyBundle(let bundleURL):
            try applyBundle(bundleURL)
        case .rollback(let command):
            try rollback(command)
        case .redisBackup:
            try createRedisBackup()
        case .redisRestore(let archive):
            try restoreRedisBackup(archive)
        case .runtimeDataBackup:
            try createRuntimeDataBackup()
        case .runtimeDataRestore(let backup):
            try restoreRuntimeDataBackup(backup)
        case .repairDatastore:
            try repairDatastore()
        case .repairVMDisk:
            try repairVMDisk()
        case .repairProxy:
            try repairProxy()
        case .repairServices:
            try repairServices()
        case .startServices:
            try startServices()
        case .stopServices:
            try stopServices()
        case .uninstall(let command):
            try uninstall(command)
        case .help:
            printUsage()
        }
    }

    func printUsage() {
        print(RuntimeLifecycleCommand.usage)
    }

    func install() throws {
        try runtimeInstallComposition().install()
    }

    func installProvision() throws {
        try runtimeInstallComposition().installProvision()
    }

    func preinstallCheck() throws {
        let document = runtimeFreshInstallPreflight()
        let data = try JSONEncoder.pretty.encode(document)
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        guard document.passed else {
            throw LauncherError.runtimeOperationFailed(
                "fresh install preflight blocked blockers=\(document.blockers.joined(separator: ","))"
            )
        }
    }

    func printStatus() {
        runtimeStatusPrinter().printStatus()
    }

    func health() throws {
        do {
            try collectGuestLogs()
        } catch {
            log("health guest log collection failed error=\(error.localizedDescription)")
        }
        try runtimeHealthCheckRunner().run()
    }

    func guestLogSync() {
        log("guest log sync started")
        while true {
            do {
                try collectGuestLogs()
            } catch {
                log("guest log sync failed error=\(error.localizedDescription)")
            }
            sleeper.sleep(forTimeInterval: Constants.Runtime.guestLogSyncIntervalSeconds)
        }
    }

    func watchdog() throws {
        try runtimeWatchdogRunner().run()
    }

    func configure(_ command: RuntimeConfigureCommand) throws {
        let result = try runtimeConfigureRunner().configure(command)

        guard result.restart else {
            try writeRuntimeStatus(.degraded, operation: .configure, message: "runtime configuration updated")
            print("runtime configuration updated; restart required for VM/guest changes")
            return
        }
        print("runtime configuration updated and services restarted")
    }

    func verifyBundle(_ bundleURL: URL) throws {
        try runtimeBundleComposition().verifyBundle(bundleURL)
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        try runtimeBundleComposition().stageBundle(bundleURL)
    }

    func applyBundle(_ bundleURL: URL) throws {
        try runtimeBundleComposition().applyBundle(bundleURL)
    }

    func repairDatastore() throws {
        try runtimeDatastoreRepairComposition().repair()
    }

    func repairVMDisk() throws {
        try runtimeVMDiskRepairComposition().repair()
    }

    func createRedisBackup() throws {
        do {
            let result = try runtimeRedisBackupComposition().createBackup()
            print(result.message)
            if let archive = result.archive, !archive.isEmpty {
                print("archive: \(archive)")
            }
        } catch RuntimeRedisBackupUseCaseError.operationFailed(let message) {
            throw LauncherError.runtimeOperationFailed(message)
        }
    }

    func createRuntimeDataBackup() throws {
        do {
            let backup = try runtimeDataBackupComposition().createBackup()
            print("runtime data backup completed")
            print("backup: \(backup.path)")
        } catch RuntimeRedisBackupUseCaseError.operationFailed(let message) {
            throw LauncherError.runtimeOperationFailed(message)
        } catch let error as RuntimeDataBackupStoreError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func restoreRedisBackup(_ archive: URL) throws {
        do {
            try runtimeDataBackupComposition().restoreRedisBackup(archive)
            print("redis restore completed")
            print("archive: \(archive.path)")
        } catch RuntimeRedisBackupUseCaseError.operationFailed(let message) {
            throw LauncherError.runtimeOperationFailed(message)
        } catch let error as RuntimeDataBackupStoreError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func restoreRuntimeDataBackup(_ backup: URL) throws {
        do {
            try runtimeDataBackupComposition().restoreBackup(backup)
            print("runtime data restore completed")
            print("backup: \(backup.path)")
        } catch RuntimeRedisBackupUseCaseError.operationFailed(let message) {
            throw LauncherError.runtimeOperationFailed(message)
        } catch let error as RuntimeDataBackupStoreError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func collectGuestLogs() throws {
        try RuntimeGuestLogCollector(installedPaths: installedPaths, fileStore: fileStore).collect()
    }

    func startServices() throws {
        try runtimeServiceControlRunner().run(.startAll)
    }

    func repairServices() throws {
        try runtimeServiceControlRunner().run(.repairAll)
    }

    func repairProxy() throws {
        try runtimeServiceControlRunner().run(.repairProxy)
    }

    func stopServices() throws {
        try runtimeServiceControlRunner().run(.stopAll)
    }

    func uninstall(_ command: RuntimeUninstallCommand) throws {
        try runtimeUninstallRunner().run(command)
    }

    func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackComposition().rollback(command)
    }

    func refreshCloudInitSeedIfNeeded(_ manifest: UpdateBundleManifest) throws {
        guard manifest.artifacts.contains(where: { $0.type == .guestDeploy }) else {
            log("cloud-init seed refresh not required")
            return
        }
        log("refreshing cloud-init seed so guest bootstrap can activate updated deploy bundle")
        try runtimeCloudInitSeedWriter().create(
            hostname: Constants.Guest.hostname,
            sshAuthorizedKeys: installedSSHAuthorizedKeys()
        )
    }

    func activateGuestUpdateIfNeeded(_ manifest: UpdateBundleManifest) throws {
        try activateRuntimeGuestUpdateIfNeeded(manifest: manifest)
    }

}

private extension RuntimeLifecycle {
    func installedSSHAuthorizedKeys() throws -> [String] {
        let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        return config.sshAuthorizedKeys ?? []
    }
}

private extension RuntimeLifecycle {
    static func prepareServiceForStop(
        _ service: RuntimeManagedService,
        paths: LauncherPaths,
        fileStore: RuntimeFileStore,
        log: @escaping (String) -> Void
    ) throws {
        guard service == .vm else {
            return
        }

        log("requesting graceful VM process stop before launchd unload")
        try StopRuntimeVMProcessUseCase().requestStopAndWait(
            terminateSignal: SIGTERM,
            noSuchProcessErrorNumber: Int32(ESRCH),
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            operations: ProcessState.stopOperations(
                pidFile: paths.pidFile,
                fileStore: fileStore,
                log: log
            )
        )
        log("VM process stopped before launchd unload")
        do {
            try RuntimeVMLifecycleStore(
                url: paths.installed.vmLifecycle,
                fileStore: fileStore
            ).write(state: .stopped, message: "VM process stopped before launchd unload")
        } catch {
            log("failed to write VM lifecycle stopped state after process stop error=\(error)")
        }
    }

    static func waitForVMProcessExitAfterGuestPoweroff(
        expectedVMProcessID: pid_t,
        paths: LauncherPaths,
        fileStore: RuntimeFileStore,
        log: @escaping (String) -> Void
    ) throws {
        log("waiting for VM process to exit after guest poweroff request pid=\(expectedVMProcessID)")
        try StopRuntimeVMProcessUseCase().waitUntilObservedProcessStopped(
            pid: Int32(expectedVMProcessID),
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            operations: ProcessState.stopOperations(
                pidFile: paths.pidFile,
                fileStore: fileStore,
                log: log
            )
        )
        log("VM process exited after guest poweroff request pid=\(expectedVMProcessID)")
    }
}
