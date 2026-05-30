import Foundation
import Core
import Contracts

extension RuntimeLifecycle {
    func runtimeInstallWorkflow() -> RuntimeInstallWorkflow {
        RuntimeInstallWorkflow(
            context: RuntimeInstallWorkflowContext(
                paths: paths,
                installedPaths: installedPaths,
                productRoot: productRoot,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeInstallWorkflowOperations(
                fileStore: fileStore,
                now: { clock.now },
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
                restrictSecretFile: restrictSecretFile,
                log: log
            )
        )
    }

    func runtimeStatusPrinter() -> RuntimeStatusPrinter {
        RuntimeStatusPrinter(
            productRoot: productRoot,
            runtimeDirectory: installedPaths.runtimeDirectory,
            runtimeStatus: runtimeStatus,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            latestBackupPath: { latestBackup()?.path },
            runtimeStatusValue: runtimeStatusValue,
            runtimeVersionValue: runtimeVersionValue,
            vmIP: { statusReporter.loadStatus()?.vmIP ?? "not reported" },
            installedProxyPort: healthChecker.installedProxyPort,
            hostProxyHTTP: { port in
                httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: port))
            },
            isExecutableFile: { path in
                fileStore.isExecutableFile(atPath: path)
            },
            fileExists: fileExists,
            serviceState: { label in
                healthChecker.launchdState(label)
            }
        )
    }

    func runtimeCloudInitSeedWriter() -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedWriter(
            installedPaths: installedPaths,
            fileStore: fileStore,
            runRequired: runRequired
        )
    }

    func runtimeHealthCheckRunner() -> RuntimeHealthCheckRunner {
        RuntimeHealthCheckRunner(
            printStatus: printStatus,
            healthSnapshot: runtimeHealthSnapshot,
            writeStatus: runtimeStatusWriterAction(),
            recordObservedEvent: { status, operation, message, snapshot in
                try runtimeObservedEventPublisher().recordObservedEvent(
                    status,
                    operation: operation,
                    message: message,
                    snapshot: snapshot,
                    defaultEventType: .healthObserved
                )
            },
            reasonText: reasonText,
            log: log,
            printLine: { line in print(line) }
        )
    }

    func automaticRecoveryEnabled() -> Bool {
        runtimeConfigFlagReader().automaticRecoveryEnabled()
    }

    func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: statusReporter,
            activeGuestBootstrap: {
                guard case .loaded(let bootstrapResult) = guestGateway.loadBootstrapResultDocument(),
                      bootstrapResult.status == .running
                else {
                    return nil
                }
                let updatedAt = bootstrapResult.updatedAt.flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
                return RuntimeGuestBootstrapOperation(
                    operation: bootstrapResult.operation ?? .install,
                    updatedAt: updatedAt
                )
            },
            now: { clock.now },
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            log: log
        )
    }

    func runtimeWatchdogRunner() -> RuntimeWatchdogRunner {
        RuntimeWatchdogRunner(
            actions: RuntimeWatchdogActions(
                prepareLogs: {
                    do {
                        try fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    } catch {
                        log("watchdog log directory preparation failed error=\(error.localizedDescription)")
                    }
                    do {
                        try rotateRuntimeLogs()
                    } catch {
                        log("watchdog log rotation failed error=\(error.localizedDescription)")
                    }
                    do {
                        try collectGuestLogs()
                    } catch {
                        log("watchdog guest log collection failed error=\(error.localizedDescription)")
                    }
                },
                activeManagedOperation: {
                    runtimeManagedOperationGuard().activeOperation()
                },
                healthSnapshot: {
                    runtimeHealthSnapshot()
                },
                proxyLivenessHTTP: { port in
                    httpProber.statusCode(url: Constants.Runtime.proxyLivenessURL(port: port))
                },
                automaticRecoveryEnabled: {
                    automaticRecoveryEnabled()
                },
                restartService: { service in
                    restartOrStartLaunchdService(service)
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                writeObservedStatus: { status, operation, message, snapshot in
                    try writeRuntimeStatus(status, operation: operation, message: message)
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
                }
            ),
            log: log
        )
    }

    func runtimeConfigureRunner() -> RuntimeConfigureRunner {
        RuntimeConfigureRunner(
            installedPaths: installedPaths,
            configURL: paths.config,
            fileStore: fileStore,
            actions: RuntimeConfigureActions(
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
                    restartOrStartLaunchdService(.vm)
                    restartOrStartLaunchdService(.guestLogSync)
                    restartOrStartLaunchdService(.proxy)
                    restartOrStartLaunchdService(.watchdog)
                }
            ),
            log: { message in
                log(message)
            }
        )
    }

    func runtimeBundleWorkflow() -> RuntimeBundleWorkflow {
        RuntimeBundleWorkflow(
            context: RuntimeBundleWorkflowContext(
                installedPaths: installedPaths,
                bundlesDirectory: bundlesDirectory,
                backupsDirectory: backupsDirectory,
                logsDirectory: logsDirectory,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeBundleWorkflowOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: runtimeHealthSnapshot,
                rotateRuntimeLogs: rotateRuntimeLogs,
                rollback: { backup in
                    try rollback(backup.map(RuntimeRollbackCommand.specificBackup) ?? .latestBackup)
                },
                startRuntimeServices: startRuntimeServices,
                stopRuntimeServices: stopRuntimeServices,
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
                log: log
            )
        )
    }

    func runtimeDatastoreRepairWorkflow() -> RuntimeDatastoreRepairWorkflow {
        RuntimeDatastoreRepairWorkflow(
            context: RuntimeDatastoreRepairWorkflowContext(
                guestRunDirectory: guestRunDirectory
            ),
            operations: RuntimeDatastoreRepairWorkflowOperations(
                createDirectory: createDirectoryAction(),
                removePreviousResult: {
                    try guestGateway.removeDatastoreRepairResult()
                },
                writeRequest: { request in
                    try guestGateway.writeDatastoreRepairRequest(request)
                },
                isVMServiceLoaded: vmServiceLoadedAction(),
                startVMService: startVMServiceAction(),
                restartVMService: restartVMServiceAction(),
                loadResult: {
                    guestGateway.loadDatastoreRepairResultDocument()
                },
                restartProxyService: {
                    restartOrStartLaunchdService(.proxy)
                },
                restartWatchdogService: {
                    restartOrStartLaunchdService(.watchdog)
                },
                waitForHealth: waitForHealth,
                writeStatus: runtimeStatusWriterAction(),
                requestID: requestIDAction(),
                timestamp: isoTimestamp,
                sleep: workflowPollingSleepAction(),
                log: log
            )
        )
    }

    func runtimeVMDiskRepairRunner() -> RuntimeVMDiskRepairRunner {
        RuntimeVMDiskRepairRunner(
            context: RuntimeVMDiskRepairContext(
                rootfsBase: rootfsBase,
                vmDisk: vmDisk,
                backupsDirectory: backupsDirectory,
                defaultDiskGiB: Constants.Defaults.defaultDiskGiB,
                freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes
            ),
            operations: RuntimeVMDiskRepairOperations(
                fileExists: fileExists,
                fileSize: fileSize,
                createDirectory: createDirectoryAction(),
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                },
                moveItem: { source, destination in
                    try fileStore.moveItem(at: source, to: destination)
                },
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
                stopRuntimeServices: stopRuntimeServices,
                startRuntimeServices: startRuntimeServices,
                waitForHealth: waitForHealth,
                writeStatus: runtimeStatusWriterAction(),
                timestamp: backupTimestamp,
                log: log
            )
        )
    }

    func runtimeServiceControlRunner() -> RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: startRuntimeServices,
            stopRuntimeServices: stopRuntimeServices,
            writeStatus: runtimeStatusWriterAction(),
            log: log
        )
    }

    func runtimeRollbackWorkflow() -> RuntimeRollbackWorkflow {
        RuntimeRollbackWorkflow(
            context: RuntimeRollbackWorkflowContext(
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                vmDisk: vmDisk,
                managerAppPath: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxDirectory: installedPaths.nginxDirectory,
                deployDirectory: installedPaths.deployDirectory
            ),
            operations: RuntimeRollbackWorkflowOperations(
                requireLatestBackup: { try backupStore().requireLatestBackup() },
                directoryExists: directoryExists,
                fileExists: fileExists,
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
        RuntimeGuestActivationWorkflow(
            context: RuntimeGuestActivationWorkflowContext(
                guestRunDirectory: guestRunDirectory
            ),
            operations: RuntimeGuestActivationWorkflowOperations(
                createDirectory: createDirectoryAction(),
                removePreviousResult: {
                    try guestGateway.removeUpdateActivationResult()
                },
                writeRequest: { request in
                    try guestGateway.writeUpdateActivationRequest(request)
                },
                isVMServiceLoaded: vmServiceLoadedAction(),
                startVMService: startVMServiceAction(),
                loadResult: {
                    guestGateway.loadUpdateActivationResultDocument()
                },
                writeStatus: runtimeStatusWriterAction(),
                requestID: requestIDAction(),
                timestamp: isoTimestamp,
                sleep: workflowPollingSleepAction(),
                log: log
            )
        )
    }

    func prepareGuestShutdownForUpdate(manifest: UpdateBundleManifest) throws {
        try RuntimeGuestShutdownRunner(
            createRunDirectory: {
                try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
            },
            removePreviousResult: {
                try guestGateway.removeUpdateShutdownResult()
            },
            requestID: requestIDAction(),
            timestamp: isoTimestamp,
            writeRequest: { request in
                try guestGateway.writeUpdateShutdownRequest(request)
            },
            loadResult: {
                guestGateway.loadUpdateShutdownResultDocument()
            },
            reportProgress: { message in
                writeRuntimeStatusBestEffort(
                    .updating,
                    operation: .applyBundle,
                    message: message,
                    writeStatus: runtimeStatusWriterAction(),
                    log: log
                )
            },
            sleep: workflowPollingSleepAction(),
            log: log
        ).prepareForUpdate(version: manifest.version)
    }
}

private extension RuntimeLifecycle {
    func runtimeWorkflowStatusReporter() -> RuntimeWorkflowStatusReporter {
        RuntimeWorkflowStatusReporter(
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

    func startVMServiceAction() -> () -> Void {
        {
            startLaunchdService(.vm)
        }
    }

    func restartVMServiceAction() -> () -> Void {
        {
            restartOrStartLaunchdService(.vm)
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
