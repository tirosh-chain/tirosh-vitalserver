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
                startRuntimeServices: startRuntimeServicesThroughStateControl,
                stopRuntimeServices: stopRuntimeServicesThroughStateControl,
                prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: prepareGuestShutdownAndStopRuntimeServicesAfterPoweroffForUpdate,
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
                acquireOperationLease: acquireRuntimeOperationLease,
                releaseOperationLease: releaseRuntimeOperationLease,
                log: log
            )
        )
    }

    private func acquireRuntimeOperationLease(_ operation: RuntimeOperation) throws -> RuntimeOperationLeaseDocument {
        let timestamp = ISO8601DateFormatter().string(from: clock.now)
        let document = RuntimeOperationLeaseDocument(
            operationId: UUID().uuidString,
            operation: operation,
            ownerPID: Int(ProcessInfo.processInfo.processIdentifier),
            startedAt: timestamp,
            heartbeatAt: timestamp,
            expiresAt: nil,
            message: nil
        )
        try JSONFileRuntimeOperationLeaseRepository(url: installedPaths.runtimeOperationLease).acquire(document)
        return document
    }

    private func releaseRuntimeOperationLease(_ document: RuntimeOperationLeaseDocument) throws {
        try JSONFileRuntimeOperationLeaseRepository(url: installedPaths.runtimeOperationLease)
            .release(operationId: document.operationId)
    }
}
