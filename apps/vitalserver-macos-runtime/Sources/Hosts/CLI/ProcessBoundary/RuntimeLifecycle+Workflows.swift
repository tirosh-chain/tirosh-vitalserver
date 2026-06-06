import Foundation
import OutboundAdapters
import Application
import Bootstrap
import Contracts
import Domain
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func runtimeInstallComposition() -> RuntimeInstallComposition {
        RuntimeInstallComposition(
            context: RuntimeInstallCompositionContext(
                paths: paths,
                installedPaths: installedPaths,
                productRoot: productRoot,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeInstallCompositionOperations(
                fileStore: fileStore,
                now: { clock.now },
                freshInstallPreflight: {
                    runtimeFreshInstallPreflightRunner().run()
                },
                installProvisionPayload: {
                    RuntimeInstallProvisionPayloadPolicy.document(
                        artifactStates: RuntimeInstallArtifactStateReader.states(
                            paths: installProvisionPayloadPaths().map(\.path)
                        )
                    )
                },
                writeRuntimeStatus: runtimeStatusWriterAction(),
                writeRuntimeProgress: runtimeProgressWriterAction(),
                rotateRuntimeLogs: rotateRuntimeLogs,
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation
                    )
                },
                runRequired: runRequired,
                runProcessToFile: runProcessToFile,
                writeInstalledRuntimeVersion: {
                    try runtimeVersionStore().writeInstalledVersion(version: Constants.launcherVersion)
                },
                setStartOnBoot: setStartOnBoot,
                startLaunchdService: startLaunchdService,
                cleanupHostProxyPortBeforeStart: cleanupHostProxyPortBeforeStart,
                waitForHealth: waitForHealth,
                restrictSecretFile: restrictSecretFile,
                log: log
            )
        )
    }

    func runtimeStatusPrinter() -> RuntimeStatusPrinter {
        RuntimeStatusPrinterComposition.make(
            context: RuntimeStatusPrinterCompositionContext(
                productRoot: productRoot,
                installedPaths: installedPaths,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeStatusPrinterCompositionOperations(
                latestBackupPath: { latestBackup()?.path },
                runtimeStatusValue: runtimeStatusValue,
                runtimeVersionValue: runtimeVersionValue,
                vmIP: { statusReporter.loadStatus()?.vmIP ?? "not reported" },
                installedProxyPort: healthChecker.installedProxyPort,
                hostProxyHTTPStatus: { url in
                    httpProber.statusCode(url: url)
                },
                isExecutableFile: { path in
                    fileStore.isExecutableFile(atPath: path)
                },
                fileExists: fileExists,
                serviceState: { label in
                    healthChecker.launchdState(label)
                }
            )
        )
    }

    func runtimeCloudInitSeedWriter() -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedComposition.make(
            runtimeDirectory: installedPaths.runtimeDirectory,
            fileStore: fileStore,
            runRequired: runRequired
        )
    }

    func runtimeHealthCheckRunner() -> RuntimeHealthCheckRunner {
        RuntimeHealthCheckRunnerComposition.make(
            operations: RuntimeHealthCheckRunnerCompositionOperations(
                printStatus: printStatus,
                healthSnapshot: runtimeHealthSnapshot,
                writeStatus: runtimeStatusWriterAction(),
                recordObservedEvent: { status, operation, message, snapshot, eventType in
                    try runtimeObservedEventPublisher().recordObservedEvent(
                        status,
                        operation: operation,
                        message: message,
                        snapshot: snapshot,
                        defaultEventType: eventType
                    )
                },
                log: log
            )
        )
    }

    func automaticRecoveryEnabled() -> Bool {
        runtimeConfigFlagReader().automaticRecoveryEnabled()
    }

    func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuardComposition.make(
            statusReporter: statusReporter,
            guestGateway: guestGateway,
            now: { clock.now },
            log: log
        )
    }

    func runtimeWatchdogRunner() -> RuntimeWatchdogRunner {
        RuntimeWatchdogRunnerComposition.make(
            context: RuntimeWatchdogRunnerCompositionContext(
                installedPaths: installedPaths,
                logsDirectory: logsDirectory
            ),
            operations: RuntimeWatchdogRunnerCompositionOperations(
                fileStore: fileStore,
                now: { clock.now },
                activeManagedOperation: {
                    runtimeManagedOperationGuard().activeOperation()
                },
                healthSnapshot: {
                    runtimeHealthSnapshot()
                },
                httpStatusCode: { url in
                    httpProber.statusCode(url: url)
                },
                automaticRecoveryEnabled: {
                    automaticRecoveryEnabled()
                },
                restartVMRuntime: {
                    try restartVMRuntimeServices()
                },
                restartService: { service in
                    try restartOrStartLaunchdService(service)
                },
                rotateRuntimeLogs: rotateRuntimeLogs,
                collectGuestLogs: collectGuestLogs,
                writeRuntimeStatus: runtimeStatusWriterAction(),
                recordObservedStatus: { status, operation, message, snapshot in
                    runtimeObservedEventPublisher().recordObservedEventBestEffort(
                        status,
                        operation: operation,
                        message: message,
                        snapshot: snapshot
                    )
                },
                recordObservedEvent: { status, operation, message, snapshot, eventType in
                    runtimeObservedEventPublisher().recordObservedEventBestEffort(
                        status,
                        operation: operation,
                        message: message,
                        snapshot: snapshot,
                        eventType: eventType
                    )
                },
                recordLifecycleEvent: { operation, message, eventType in
                    runtimeEventPublisher().recordLifecycleEventBestEffort(
                        operation: operation,
                        message: message,
                        eventType: eventType
                    )
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                log: log
            )
        )
    }

    func runtimeConfigureRunner() -> RuntimeConfigureRunner {
        RuntimeConfigureComposition.make(
            context: RuntimeConfigureCompositionContext(
                installedPaths: installedPaths,
                configURL: paths.config
            ),
            operations: RuntimeConfigureCompositionOperations(
                fileStore: fileStore,
                resizeVMDiskIfNeeded: { diskGiB in
                    try resizeVMDiskIfNeeded(diskGiB: diskGiB)
                },
                setInstalledProxyPort: { port in
                    try setInstalledProxyPort(port)
                },
                readSecretFile: { url in
                    try readSecretFile(url)
                },
                restrictSecretFile: { url in
                    try restrictSecretFile(url)
                },
                setStartOnBoot: { enabled in
                    try setStartOnBoot(enabled)
                },
                setSystemSleepPrevention: { enabled in
                    try setSystemSleepPrevention(enabled)
                },
                restartRuntimeServices: {
                    try restartVMRuntimeServices()
                    try restartOrStartLaunchdService(.proxy)
                    try restartOrStartLaunchdService(.watchdog)
                },
                log: log
            )
        )
    }

    func runtimeBundleComposition() -> RuntimeBundleComposition {
        RuntimeBundleComposition(
            context: RuntimeBundleCompositionContext(
                installedPaths: installedPaths,
                bundlesDirectory: bundlesDirectory,
                backupsDirectory: backupsDirectory,
                logsDirectory: logsDirectory,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeBundleCompositionOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: runtimeHealthSnapshot,
                rotateRuntimeLogs: rotateRuntimeLogs,
                rollback: { backup in
                    try rollback(backup.map(RuntimeRollbackCommand.specificBackup) ?? .latestBackup)
                },
                startRuntimeServices: startRuntimeServices,
                stopRuntimeServices: stopRuntimeServices,
                runningVMProcessID: runningVMProcessID,
                stopRuntimeServicesAfterGuestPoweroff: stopRuntimeServicesAfterGuestPoweroff,
                prepareGuestShutdownForUpdate: prepareGuestShutdownForUpdate,
                clearGuestShutdownPreparation: {
                    try guestGateway.removeUpdateShutdownResult()
                },
                isLaunchdLoaded: isLaunchdLoaded,
                createBackup: { reason in try backupStore().createBackup(reason: reason) },
                statusReporter: runtimeWorkflowStatusReporter(),
                pruneOldRuntimeArtifacts: {
                    try storageMaintenance().pruneOldRuntimeArtifacts(
                        backupsDirectory: backupsDirectory,
                        bundlesDirectory: bundlesDirectory
                    )
                },
                reasonText: reasonText,
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation.rawValue
                    )
                },
                runProcess: runProcess,
                runRequired: runRequired,
                runProcessToFile: runProcessToFile,
                replaceFile: { source, destination in try storageMaintenance().replaceFile(from: source, to: destination) },
                writeRuntimeVersion: { version, bundle in try writeRuntimeVersion(version: version, bundle: bundle) },
                refreshCloudInitSeedIfNeeded: refreshCloudInitSeedIfNeeded,
                activateGuestUpdateIfNeeded: activateGuestUpdateIfNeeded,
                waitForHealth: waitForHealth,
                requireGuestCapability: requireGuestCapability,
                log: log
            )
        )
    }

    func runtimeDatastoreRepairWorkflow() -> RuntimeDatastoreRepairWorkflow {
        RuntimeDatastoreRepairComposition(
            context: RuntimeDatastoreRepairCompositionContext(
                guestRunDirectory: guestRunDirectory
            ),
            operations: RuntimeDatastoreRepairCompositionOperations(
                fileStore: fileStore,
                guestGateway: guestGateway,
                requireCapability: {
                    try requireGuestCapability(.repairDatastore)
                },
                isVMServiceLoaded: vmServiceLoadedAction(),
                startVMService: startVMServiceAction(),
                restartVMService: restartVMServiceAction(),
                restartProxyService: {
                    try restartOrStartLaunchdService(.proxy)
                },
                restartWatchdogService: {
                    try restartOrStartLaunchdService(.watchdog)
                },
                waitForHealth: waitForHealth,
                writeStatus: runtimeStatusWriterAction(),
                requestID: requestIDAction(),
                timestamp: isoTimestamp,
                sleep: workflowPollingSleepAction(),
                log: log
            )
        ).workflow()
    }

    func runtimeVMDiskRepairRunner() -> RuntimeVMDiskRepairRunner {
        RuntimeVMDiskRepairComposition.make(
            context: RuntimeVMDiskRepairCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeVMDiskRepairCompositionOperations(
                fileStore: fileStore,
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation
                    )
                },
                runProcessToFile: runProcessToFile,
                runRequired: runRequired,
                createRedisBackup: createRedisBackup,
                stopRuntimeServicesForVMDiskReplacement: stopRuntimeServicesForVMDiskReplacement,
                startRuntimeServices: startRuntimeServices,
                waitForHealth: waitForHealth,
                writeStatus: runtimeStatusWriterAction(),
                timestamp: backupTimestamp,
                log: log
            )
        )
    }

    func runtimeServiceControlRunner() -> RuntimeServiceControlRunner {
        RuntimeServiceControlComposition.make(
            operations: RuntimeServiceControlCompositionOperations(
                startRuntimeServices: startRuntimeServices,
                stopRuntimeServices: stopRuntimeServices,
                launchdState: { service in
                    healthChecker.launchdState(service)
                },
                writeStatus: runtimeStatusWriterAction(),
                log: log
            )
        )
    }

    func runtimeRedisBackupWorkflow() -> RuntimeRedisBackupWorkflow {
        RuntimeRedisBackupComposition(
            context: RuntimeRedisBackupCompositionContext(
                guestRunDirectory: guestRunDirectory,
                redisBackupsDirectory: installedPaths.redisBackupsDirectory
            ),
            operations: RuntimeRedisBackupCompositionOperations(
                fileStore: fileStore,
                requireCapability: {
                    try requireGuestCapability(.redisBackup)
                },
                writeRuntimeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                requestID: {
                    UUID().uuidString
                },
                timestamp: isoTimestamp,
                isVMServiceLoaded: {
                    isLaunchdLoaded(.vm)
                },
                startVMService: {
                    try startLaunchdService(.vm)
                },
                sleep: { seconds in
                    sleeper.sleep(forTimeInterval: seconds)
                },
                log: log
            )
        ).workflow()
    }

    func runtimeRollbackWorkflow() -> RuntimeRollbackWorkflow {
        RuntimeRollbackComposition.make(
            context: RuntimeRollbackCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeRollbackCompositionOperations(
                fileStore: fileStore,
                requireLatestBackup: { try backupStore().requireLatestBackup() },
                isLaunchdLoaded: isLaunchdLoaded,
                stopRuntimeServices: stopRuntimeServices,
                startRuntimeServices: startRuntimeServices,
                waitForHealth: waitForHealth,
                replaceFile: { source, destination in try storageMaintenance().replaceFile(from: source, to: destination) },
                writeRuntimeVersion: { version, bundle in try writeRuntimeVersion(version: version, bundle: bundle) },
                restoreBackupPathIfExists: { source, destination in
                    try backupStore().restoreBackupPathIfExists(source, to: destination)
                },
                restoreRuntimeToolsIfExists: { source in try backupStore().restoreRuntimeToolsIfExists(source) },
                writeStatus: runtimeStatusWriterAction(),
                writeProgress: runtimeProgressWriterAction(),
                log: log
            )
        )
    }

    func runtimeGuestActivationWorkflow() -> RuntimeGuestActivationWorkflow {
        RuntimeGuestActivationComposition(
            context: RuntimeGuestActivationCompositionContext(
                guestRunDirectory: guestRunDirectory
            ),
            operations: RuntimeGuestActivationCompositionOperations(
                fileStore: fileStore,
                guestGateway: guestGateway,
                requireCapability: {
                    try requireGuestCapability(.activateUpdate)
                },
                isVMServiceLoaded: vmServiceLoadedAction(),
                startVMService: startVMServiceAction(),
                writeStatus: runtimeStatusWriterAction(),
                requestID: requestIDAction(),
                timestamp: isoTimestamp,
                sleep: workflowPollingSleepAction(),
                log: log
            )
        ).workflow()
    }

    func prepareGuestShutdownForUpdate(manifest: UpdateBundleManifest) throws {
        try RuntimeGuestShutdownComposition(
            context: RuntimeGuestShutdownCompositionContext(
                guestRunDirectory: guestRunDirectory
            ),
            operations: RuntimeGuestShutdownCompositionOperations(
                fileStore: fileStore,
                guestGateway: guestGateway,
                requireCapability: {
                    try requireGuestCapability(.prepareUpdateShutdown)
                },
                writeStatus: runtimeStatusWriterAction(),
                requestID: requestIDAction(),
                timestamp: isoTimestamp,
                sleep: workflowPollingSleepAction(),
                log: log
            )
        ).workflow().prepareForUpdate(manifest: manifest)
    }

    func requireGuestCapability(_ capability: RuntimeGuestCapabilityRequirement) throws {
        try RuntimeGuestCapabilityCheckerComposition.make(
            guestGateway: guestGateway
        ).require(capability)
    }
}

private extension RuntimeLifecycle {
    func runtimeWorkflowStatusReporter() -> RuntimeWorkflowStatusReporter {
        RuntimeWorkflowStatusReporterComposition.make(
            writeStatus: runtimeStatusWriterAction(),
            writeProgress: runtimeProgressWriterAction(),
            log: log
        )
    }

    func runtimeStatusWriterAction() -> (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void {
        { status, operation, message in
            try writeRuntimeStatus(status, operation: operation, message: message)
        }
    }

    func runtimeProgressWriterAction() -> (RuntimeStepExecutionEvent) throws -> Void {
        { event in
            try writeRuntimeProgress(
                event.status,
                operation: event.operation,
                step: event.step,
                stepStatus: event.stepStatus,
                phase: event.phase,
                message: event.message
            )
        }
    }

    func createDirectoryAction() -> (URL, Bool) throws -> Void {
        { url, withIntermediateDirectories in
            try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
        }
    }

    func vmServiceLoadedAction() -> () -> Bool {
        {
            isLaunchdLoaded(.vm)
        }
    }

    func startVMServiceAction() -> () throws -> Void {
        {
            try startLaunchdService(.vm)
        }
    }

    func restartVMServiceAction() -> () throws -> Void {
        {
            try restartVMRuntimeServices()
        }
    }

    func requestIDAction() -> () -> String {
        {
            UUID().uuidString
        }
    }

    func workflowPollingSleepAction() -> () -> Void {
        {
            sleeper.sleep(forTimeInterval: 3)
        }
    }
}
