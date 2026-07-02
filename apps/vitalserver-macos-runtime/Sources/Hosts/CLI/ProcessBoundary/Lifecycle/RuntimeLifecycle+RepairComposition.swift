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
                waitForHealth: waitForHealth,
                writeStatus: runtimeStatusWriterAction(),
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
                stopRuntimeServices: stopRuntimeServicesThroughStateControl,
                startRuntimeServices: startRuntimeServicesThroughStateControl,
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
                requireCapability: {
                    try requireGuestCapability(.activateUpdate)
                },
                activateUpdate: { requestID, version in
                    try activateUpdateThroughGuestControl(
                        requestID: requestID,
                        version: version
                    )
                },
                isVMServiceLoaded: vmServiceLoadedAction(),
                startVMService: startVMServiceAction(),
                requestID: requestIDAction(),
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
                requireCapability: {
                    try requireGuestCapability(.prepareUpdateShutdown)
                },
                prepareUpdateShutdown: { requestID, version in
                    try prepareUpdateShutdownThroughGuestControl(
                        requestID: requestID,
                        version: version
                    )
                },
                loadOperation: { operationID in
                    try guestControlOperationThroughGuestControl(operationID)
                },
                requestGuestPoweroff: {
                    try requestGuestPoweroffThroughGuestControl()
                },
                writeStatus: runtimeStatusWriterAction(),
                requestID: requestIDAction(),
                sleep: workflowPollingSleepAction(),
                log: log
            )
        ).prepareForUpdate(manifest: manifest)
    }

    func requireGuestCapability(_ capability: RuntimeGuestCapabilityRequirement) throws {
        try RuntimeGuestCapabilityCheckerComposition.require(
            capability,
            guestControlGateway: try guestControlGateway()
        )
    }
}
