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
    func runtimeInstallComposition() -> RuntimeInstallComposition<RuntimeInstallSettings> {
        RuntimeInstallComposition(
            context: RuntimeInstallCompositionContext(
                paths: paths,
                installedPaths: installedPaths
            ),
            operations: RuntimeInstallCompositionOperations(
                fileStore: fileStore,
                now: { clock.now },
                loadInstallSettings: {
                    try RuntimeInstallSettings.load(
                        defaultVitalFilesDirectory: installedPaths.vitalFilesDirectory.path,
                        fileStore: fileStore
                    )
                },
                freshInstallPreflight: {
                    runtimeFreshInstallPreflight()
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
                prepareInstallDirectories: { settings in
                    try runtimeInstallDirectoryPreparer().prepare(settings: settings)
                },
                rotateRuntimeLogs: rotateRuntimeLogs,
                configureDeployEnvironment: configureDeployEnvironment,
                prepareInstalledExecutables: prepareInstalledExecutables,
                provisionVMDisk: provisionVMDisk,
                configureInstalledVMRuntime: configureInstalledVMRuntime,
                createCloudInitSeed: createCloudInitSeed,
                writeInstalledRuntimeVersion: {
                    try runtimeVersionStore().writeInstalledVersion(version: Constants.launcherVersion)
                },
                configureInstalledPermissions: configureInstalledPermissions,
                startInstalledServices: startInstalledServices,
                applyStartOnBootPolicy: applyStartOnBootPolicy,
                waitInstallRuntimeHealth: { settings in
                    try waitForHealth(runtimeServiceRestartPolicy(settings))
                },
                cleanupInstallSettings: cleanupInstallSettings,
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
            buildSeedImage: buildCloudInitSeedImage
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

    func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuardComposition {
        RuntimeManagedOperationGuardComposition.make(
            statusReporter: statusReporter,
            guestGateway: guestGateway,
            now: { clock.now },
            log: log
        )
    }

    func runtimeWatchdogRunner() -> RuntimeWatchdogRunnerComposition {
        RuntimeWatchdogRunnerComposition(
            context: RuntimeWatchdogRunnerCompositionContext(
                installedPaths: installedPaths
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
                proxyLivenessURL: { port in
                    Constants.Runtime.proxyLivenessURL(port: port)
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
                createLogsDirectory: {
                    runtimeBestEffortResult {
                        try fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    }
                },
                rotateRuntimeLogs: {
                    runtimeBestEffortResult {
                        try rotateRuntimeLogs()
                    }
                },
                collectGuestLogs: {
                    runtimeBestEffortResult {
                        try collectGuestLogs()
                    }
                },
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
                recoveryWaitSeconds: Constants.Runtime.watchdogRecoveryWaitSeconds,
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
                configURL: paths.config,
                maximumAllowedCPUCount: Constants.Defaults.maximumAllowedCPUCount(
                    systemCPUCount: ProcessInfo.processInfo.processorCount
                ),
                maximumAllowedMemoryGiB: Constants.Defaults.maximumAllowedMemoryGiB(
                    physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
                )
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
                materializeBundle: materializeRuntimeUpdateBundle,
                executeMaterializationCleanupPlan: executeBundleMaterializationCleanupPlan,
                removeMaterializedBundleTemporaryRoot: removeMaterializedBundleTemporaryRoot,
                stageMaterializedBundle: stageRuntimeUpdateBundle,
                validateUpdateArtifactPayload: validateRuntimeUpdateArtifactPayload,
                replaceUpdateArtifacts: replaceRuntimeUpdateArtifacts,
                runMigrations: runRuntimeUpdateMigrations,
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation.rawValue
                    )
                },
                directorySize: { url in
                    try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
                },
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

    func runtimeDatastoreRepairComposition() -> RuntimeDatastoreRepairComposition {
        container.makeRuntimeDatastoreRepairComposition(actions: runtimeRepairCompositionActions())
    }

    func runtimeVMDiskRepairComposition() -> RuntimeVMDiskRepairComposition {
        container.makeRuntimeVMDiskRepairComposition(actions: runtimeRepairCompositionActions())
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

    func runtimeRedisBackupComposition() -> RuntimeRedisBackupComposition {
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
        )
    }

    func runtimeRollbackComposition() -> RuntimeRollbackComposition {
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

    func activateRuntimeGuestUpdateIfNeeded(manifest: UpdateBundleManifest) throws {
        try RuntimeGuestActivationComposition(
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
        ).activateIfNeeded(manifest: manifest)
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
        ).prepareForUpdate(manifest: manifest)
    }

    func requireGuestCapability(_ capability: RuntimeGuestCapabilityRequirement) throws {
        try RuntimeGuestCapabilityCheckerComposition.require(
            capability,
            guestGateway: guestGateway
        )
    }
}

private extension RuntimeLifecycle {
    func runtimeBestEffortResult(_ action: () throws -> Void) -> RuntimeBestEffortOperationResult {
        do {
            try action()
            return .completed
        } catch {
            return .failed(reason: RuntimeErrorDescription.describe(error))
        }
    }

    func runtimeRepairCompositionActions() -> RuntimeRepairCompositionActions {
        RuntimeRepairCompositionActions(
            requireDatastoreRepairCapability: {
                try requireGuestCapability(.repairDatastore)
            },
            requireRedisBackupCapability: {
                try requireGuestCapability(.redisBackup)
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
            backupTimestamp: backupTimestamp,
            requireFreeSpace: { url, minimumBytes, operation in
                try storageMaintenance().requireFreeSpace(
                    at: url,
                    minimumBytes: minimumBytes,
                    operation: operation
                )
            },
            createReplacementVMDisk: createReplacementVMDisk,
            createRedisBackup: {
                do {
                    try createRedisBackup()
                    return .completed
                } catch {
                    return .failed(reason: RuntimeErrorDescription.describe(error))
                }
            },
            stopRuntimeServicesForVMDiskReplacement: stopRuntimeServicesForVMDiskReplacement,
            startRuntimeServices: startRuntimeServices,
            log: log
        )
    }

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
