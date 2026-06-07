import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
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
