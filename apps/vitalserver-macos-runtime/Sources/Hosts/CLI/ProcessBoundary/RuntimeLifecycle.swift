import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Errors
import RuntimeControl
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
    let guestAddressProvider: any RuntimeGuestAddressProvider
    let guestControlGatewayFactory: (() throws -> any RuntimeGuestControlGateway)?
    let runtimeOperationLeaseOwnerFactory: () -> any RuntimeOperationLeaseOwner
    let fileStore: RuntimeFileStore

    init(
        paths: LauncherPaths,
        clock: RuntimeClock = SystemRuntimeClock(),
        sleeper: RuntimeSleeper = ThreadRuntimeSleeper(),
        commandRunner: RuntimeCommandRunner = SystemRuntimeCommandRunner(),
        httpProber: RuntimeHTTPProber? = nil,
        serviceManager: RuntimeServiceManager? = nil,
        runtimeStatusArtifactSink: RuntimeStatusArtifactSink? = nil,
        runtimeProgressArtifactSink: RuntimeProgressArtifactSink? = nil,
        guestAddressProvider: (any RuntimeGuestAddressProvider)? = nil,
        runtimeOperationLeaseOwnerFactory: (() -> any RuntimeOperationLeaseOwner)? = nil,
        guestControlGatewayFactory: (() throws -> any RuntimeGuestControlGateway)? = nil,
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
            runtimeStatusArtifactSink: runtimeStatusArtifactSink,
            runtimeProgressArtifactSink: runtimeProgressArtifactSink,
            guestAddressProvider: guestAddressProvider,
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
        self.guestAddressProvider = container.guestAddressProvider
        self.guestControlGatewayFactory = guestControlGatewayFactory
        self.runtimeOperationLeaseOwnerFactory = runtimeOperationLeaseOwnerFactory ?? {
            SQLiteRuntimeOperationLeaseRepository(
                databaseURL: container.installedPaths.runtimeStateDatabase
            )
        }
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
        case .installProvision(let packageInstallContract):
            try installProvision(packageInstallContract: packageInstallContract)
        case .preinstallCheck(let packageInstallContract):
            try preinstallCheck(packageInstallContract: packageInstallContract)
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
        case .applyBundle(let command):
            try applyBundle(command)
        case .applyUpdateBootstrap(let command):
            try applyUpdateBootstrap(command)
        case .resumeUpdateBootstrapHandoff(let command):
            try resumeUpdateBootstrapHandoff(command)
        case .settleUpdateBootstrapHandoff(let command):
            try settleUpdateBootstrapHandoff(command)
        case .failUpdateBootstrap(let command):
            try failUpdateBootstrap(command)
        case .rollback(let command):
            try rollback(command)
        case .redisBackup:
            try createRedisBackup()
        case .redisRestore(let archive):
            try restoreRedisBackup(archive)
        case .runtimeDataBackup:
            try createRuntimeDataBackup()
        case .automaticBackup:
            try createAutomaticBackup()
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
        case .stopPackageServices:
            try stopRuntimeServicesForUninstall()
        case .guestStackStatus(let command):
            try printGuestStackStatus(command)
        case .guestServiceStart(let command):
            try startGuestService(command)
        case .guestServiceStop(let command):
            try stopGuestService(command)
        case .guestServiceRestart(let command):
            try restartGuestService(command)
        case .vitalDB(let command):
            try runVitalDBCommand(command)
        case .lab(let command):
            try runLabCommand(command)
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

    func installProvision(packageInstallContract: URL) throws {
        _ = try loadPackageInstallContract(from: packageInstallContract)
        try runtimeInstallComposition().installProvision()
    }

    func preinstallCheck(packageInstallContract: URL) throws {
        let document = runtimeFreshInstallPreflight()
        let targetVersion = try packageTargetVersion()
        let data = try JSONEncoder.pretty.encode(document)
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        switch RuntimePackageInstallPreflightPolicy.disposition(
            document: document,
            targetVersion: targetVersion
        ) {
        case .fresh:
            try writePackageInstallContract(
                targetVersion: targetVersion,
                intent: .fresh,
                to: packageInstallContract
            )
            print("package install disposition=fresh targetVersion=\(targetVersion.rawValue)")
        case .blocked(let blockers):
            throw LauncherError.runtimeOperationFailed(
                "package install preflight blocked blockers=\(blockers.joined(separator: ","))"
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
            if result.restartRequirement.requiresRestart {
                let message = configureActivationRequiredMessage(result.restartRequirement)
                try writeRuntimeStatus(
                    .degraded,
                    operation: .configure,
                    message: message
                )
                print(message)
                return
            }
            try writeRuntimeStatus(.healthy, operation: .configure, message: "runtime configuration updated")
            print("runtime configuration updated")
            return
        }
        print("runtime configuration updated and required runtime changes activated")
    }

    private func configureActivationRequiredMessage(
        _ requirement: ConfigureRuntimeRestartRequirement
    ) -> String {
        switch requirement {
        case .none:
            return "runtime configuration updated"
        case .guestStack:
            return "runtime configuration updated; guest stack reconcile required"
        case .vmRuntime:
            return "runtime configuration updated; VM runtime restart required"
        }
    }

    func verifyBundle(_ bundleURL: URL) throws {
        try runtimeBundleComposition().verifyBundle(bundleURL)
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        try runtimeBundleComposition().stageBundle(bundleURL)
    }

    func applyBundle(_ command: RuntimeApplyBundleCommand) throws {
        try runtimeBundleComposition().applyBundle(
            command.bundleURL,
            trustIntent: command.trustIntent
        )
    }

    func repairDatastore() throws {
        try runtimeDatastoreRepairComposition().repair()
    }

    func repairVMDisk() throws {
        try runtimeVMDiskRepairComposition().repair()
    }

    func createRedisBackup() throws {
        let operation = try createRedisBackupThroughGuestControl()
        print("redis backup completed")
        print("operation: \(operation.operationId)")
        if let archive = operation.result?.archive, !archive.isEmpty {
            print("archive: \(archive)")
        }
    }

    func createRuntimeDataBackup() throws {
        do {
            let result = try runtimeDataBackupComposition().createBackup()
            print("runtime data backup completed")
            print("backup: \(result.backup.path)")
            for failure in result.cleanupFailures {
                print(
                    "maintenance archive cleanup failed: "
                        + "\(failure.archive.path): \(failure.reason)"
                )
            }
        } catch let error as RuntimeDataBackupStoreError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func createAutomaticBackup() throws {
        do {
            let result = try runtimeDataBackupComposition().createAutomaticBackup()
            print(result.message)
        } catch let error as RuntimeDataBackupStoreError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func restoreRedisBackup(_ archive: URL) throws {
        let stagedRedisArchive = try runtimeDataBackupComposition()
            .stageRedisArchiveForGuestRestore(archive)
        defer {
            try? fileStore.removeItem(at: stagedRedisArchive.hostURL)
        }
        let operation = try restoreRedisBackupThroughGuestControl(
            guestArchivePath: stagedRedisArchive.guestPath
        )
        print("redis restore completed")
        print("operation: \(operation.operationId)")
        if let restoredArchive = operation.result?.restoredArchive,
           !restoredArchive.isEmpty {
            print("archive: \(restoredArchive)")
        }
    }

    func restoreRuntimeDataBackup(_ backup: URL) throws {
        let step = RuntimeWorkflowStep.restoreRuntimeDataBackup
        publishRuntimeDataRestoreProgress(
            step: step,
            stepStatus: .started,
            phase: .running,
            message: "Restoring VitalServer backup: \(backup.path)"
        )
        do {
            try runtimeDataBackupComposition().restoreBackup(backup)
            publishRuntimeDataRestoreProgress(
                step: step,
                stepStatus: .completed,
                phase: .completed,
                message: "VitalServer restore completed: \(backup.path)"
            )
            print("runtime data restore completed")
            print("backup: \(backup.path)")
        } catch let error as RuntimeDataBackupStoreError {
            publishRuntimeDataRestoreFailure(step: step, backup: backup, message: error.description)
            throw LauncherError.runtimeOperationFailed(error.description)
        } catch {
            let message = error.localizedDescription
            publishRuntimeDataRestoreFailure(step: step, backup: backup, message: message)
            throw error
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

    func restartGuestService(_ command: RuntimeGuestServiceControlCommand) throws {
        try runGuestServiceCommand(command, action: .restart)
    }

    func startGuestService(_ command: RuntimeGuestServiceControlCommand) throws {
        try runGuestServiceCommand(command, action: .start)
    }

    func stopGuestService(_ command: RuntimeGuestServiceControlCommand) throws {
        try runGuestServiceCommand(command, action: .stop)
    }

    func printGuestStackStatus(_ command: RuntimeGuestControlReadCommand) throws {
        do {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: try resolvedGuestControlBaseURL(command.guestControlBaseURL)
            )
            try printJSON(gateway.stackStatus())
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    private func runGuestServiceCommand(
        _ command: RuntimeGuestServiceControlCommand,
        action: GuestProductServiceAction
    ) throws {
        do {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: try resolvedGuestControlBaseURL(command.guestControlBaseURL)
            )
            let usecase = RuntimeGuestProductServiceControlUseCase()
            let operation: RuntimeGuestControlServiceOperation
            switch action {
            case .start:
                operation = try usecase.startService(command.service, gateway: gateway)
            case .stop:
                operation = try usecase.stopService(command.service, gateway: gateway)
            case .restart:
                operation = try usecase.restartService(command.service, gateway: gateway)
            case .reconcile:
                operation = try usecase.reconcileServices(gateway: gateway)
            }
            try printJSON(operation)
        } catch RuntimeServiceControlError.operationFailed(let message) {
            throw LauncherError.runtimeOperationFailed(message)
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func runLabCommand(_ command: RuntimeLabControlCommand) throws {
        do {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: try resolvedGuestControlBaseURL(command.guestControlBaseURL)
            )
            switch command.action {
            case .scenarios:
                try printJSON(gateway.labScenarios())
            case .beds:
                try printJSON(gateway.labBeds())
            case .recorders:
                try printJSON(gateway.labRecorders())
            case .createSession(let request):
                try printJSON(gateway.createLabSession(request))
            case .getSession(let sessionId):
                try printJSON(gateway.labSession(sessionId))
            case .startSession(let sessionId):
                try printJSON(gateway.startLabSession(sessionId))
            case .stopSession(let sessionId):
                try printJSON(gateway.stopLabSession(sessionId))
            case .finishSession(let sessionId):
                try printJSON(gateway.finishLabSession(sessionId))
            case .replayVitalFile(let request):
                try printJSON(gateway.replayLabVitalFile(request))
            }
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    func runVitalDBCommand(_ command: RuntimeVitalDBReadCommand) throws {
        do {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: try resolvedGuestControlBaseURL(command.guestControlBaseURL)
            )
            switch command.action {
            case .observation:
                try printJSON(gateway.latestVitalDBObservation())
            case .recorders:
                try printJSON(gateway.vitalDBRecorders())
            case .recorderActivity(let vrcode):
                try printJSON(gateway.vitalDBRecorderActivity(vrcode))
            case .beds:
                try printJSON(gateway.vitalDBBeds())
            case .relationships:
                try printJSON(gateway.vitalDBRelationships())
            }
        } catch let error as RuntimeGuestControlHTTPGatewayError {
            throw LauncherError.runtimeOperationFailed(error.description)
        }
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder.pretty.encode(value)
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    func uninstall(_ command: RuntimeUninstallCommand) throws {
        try runtimeUninstallRunner().run(command)
    }

    func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackComposition().rollback(
            command,
            invocation: .standalone(
                operationID: UUID().uuidString.lowercased(),
                startedAt: ISO8601DateFormatter().string(from: clock.now)
            )
        )
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
    func publishRuntimeDataRestoreFailure(
        step: RuntimeWorkflowStep,
        backup: URL,
        message: String
    ) {
        publishRuntimeDataRestoreProgress(
            step: step,
            stepStatus: .failed,
            phase: .failed,
            message: "VitalServer restore failed: \(message) backup=\(backup.path)",
            reasonCodes: ["runtime-data-restore-failed"]
        )
    }

    func publishRuntimeDataRestoreProgress(
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) {
        do {
            try writeRuntimeProgress(
                .recovering,
                operation: .runtimeDataRestore,
                step: step,
                stepStatus: stepStatus,
                phase: phase,
                message: message,
                reasonCodes: reasonCodes
            )
        } catch {
            log("runtime data restore progress write failed error=\(error.localizedDescription) message=\(message)")
        }
    }

    func installedSSHAuthorizedKeys() throws -> [String] {
        let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        return config.sshAuthorizedKeys ?? []
    }
}


private enum GuestProductServiceAction {
    case start
    case stop
    case restart
    case reconcile
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
            let owner = SQLiteRuntimeVMLifecycleResourceStore(
                databaseURL: paths.installed.runtimeStateDatabase,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            )
            let read = owner.loadVMLifecycleResource()
            guard read.state == .loaded, let current = read.document else {
                log("skipped VM lifecycle stopped write after process stop state=\(read.state.rawValue) error=\(read.readError ?? "none")")
                return
            }
            _ = try owner.putVMLifecycleResource(RuntimeVMLifecycleDocument(
                state: .stopped,
                operation: current.operation,
                operationID: current.operationID,
                bootID: current.bootID,
                startedAt: current.startedAt,
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                deadlineAt: nil,
                terminalReason: nil,
                message: "VM process stopped before launchd unload"
            ))
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
        try RuntimeVMLifecycleProcessExitReconciler.reconcile(
            expectedVMProcessID: expectedVMProcessID,
            paths: paths,
            log: log
        )
    }
}
