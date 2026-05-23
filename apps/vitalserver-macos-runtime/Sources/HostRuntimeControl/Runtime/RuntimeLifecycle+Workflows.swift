import Foundation
import RuntimeCore
import RuntimeContracts

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
                writeRuntimeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                writeRuntimeProgress: { event in
                    try writeRuntimeProgress(
                        event.status,
                        operation: event.operation,
                        step: event.step,
                        stepStatus: event.stepStatus,
                        phase: event.phase,
                        message: event.message
                    )
                },
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
            vmIP: { healthChecker.guestRuntimeState()?.vmIP ?? healthChecker.readTrimmed(vmIPFile) ?? "waiting" },
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
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            reasonText: reasonText,
            printLine: { line in print(line) }
        )
    }

    func automaticRecoveryEnabled() -> Bool {
        guard let config = try? VMRuntimeConfig.load(from: paths.config, fileStore: fileStore) else {
            return true
        }
        return config.autoRecoveryEnabled ?? true
    }

    func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: statusReporter,
            now: { clock.now },
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            log: log
        )
    }

    func runtimeWatchdogRunner() -> RuntimeWatchdogRunner {
        RuntimeWatchdogRunner(
            actions: RuntimeWatchdogActions(
                prepareLogs: {
                    try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    try? rotateRuntimeLogs()
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
                    restartLaunchdService(service)
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
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
                restartRuntimeServices: {
                    restartLaunchdService(.vm)
                    restartLaunchdService(.proxy)
                    restartLaunchdService(.watchdog)
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
                isLaunchdLoaded: isLaunchdLoaded,
                createBackup: { reason in try backupStore().createBackup(reason: reason) },
                writeRuntimeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                writeRuntimeProgress: { event in
                    try writeRuntimeProgress(
                        event.status,
                        operation: event.operation,
                        step: event.step,
                        stepStatus: event.stepStatus,
                        phase: event.phase,
                        message: event.message
                    )
                },
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
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                removePreviousResult: {
                    try guestGateway.removeDatastoreRepairResult()
                },
                writeRequest: { request in
                    try guestGateway.writeDatastoreRepairRequest(request)
                },
                isVMServiceLoaded: {
                    isLaunchdLoaded(.vm)
                },
                startVMService: {
                    startLaunchdService(.vm)
                },
                restartVMService: {
                    restartLaunchdService(.vm)
                },
                loadResult: {
                    guestGateway.loadDatastoreRepairResult()
                },
                restartProxyService: {
                    restartLaunchdService(.proxy)
                },
                restartWatchdogService: {
                    restartLaunchdService(.watchdog)
                },
                waitForHealth: waitForHealth,
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                requestID: {
                    UUID().uuidString
                },
                timestamp: isoTimestamp,
                sleep: {
                    sleeper.sleep(forTimeInterval: 3)
                },
                log: log
            )
        )
    }

    func runtimeServiceControlRunner() -> RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: startRuntimeServices,
            stopRuntimeServices: stopRuntimeServices,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
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
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                writeProgress: { event in
                    try writeRuntimeProgress(
                        event.status,
                        operation: event.operation,
                        step: event.step,
                        stepStatus: event.stepStatus,
                        phase: event.phase,
                        message: event.message
                    )
                },
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
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                removePreviousResult: {
                    try guestGateway.removeUpdateActivationResult()
                },
                writeRequest: { request in
                    try guestGateway.writeUpdateActivationRequest(request)
                },
                isVMServiceLoaded: {
                    isLaunchdLoaded(.vm)
                },
                startVMService: {
                    startLaunchdService(.vm)
                },
                loadResult: {
                    guestGateway.loadUpdateActivationResult()
                },
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                requestID: { UUID().uuidString },
                timestamp: isoTimestamp,
                sleep: {
                    sleeper.sleep(forTimeInterval: 3)
                },
                log: log
            )
        )
    }
}
