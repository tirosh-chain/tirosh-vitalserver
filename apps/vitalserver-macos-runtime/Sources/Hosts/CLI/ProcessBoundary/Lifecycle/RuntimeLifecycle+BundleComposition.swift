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
                installedChannel: Constants.launcherChannel,
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
                rollback: { backup, operationLease in
                    try runtimeRollbackComposition().rollback(
                        backup.map(RuntimeRollbackCommand.specificBackup) ?? .latestBackup,
                        invocation: .applyBundleRecovery(
                            parentOperationID: operationLease.operationId
                        )
                    )
                },
                startRuntimeServices: startRuntimeServicesThroughStateControl,
                stopRuntimeServices: stopRuntimeServicesThroughStateControl,
                prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: prepareGuestShutdownAndStopRuntimeServicesAfterPoweroffForUpdate,
                isLaunchdLoaded: isLaunchdLoaded,
                createBackup: { reason in try backupStore().createBackup(reason: reason) },
                statusReporter: runtimeWorkflowStatusReporter(),
                workflowOperationStateRepository: runtimeWorkflowOperationStateRepository(),
                workflowOperationStateTimestamp: {
                    ISO8601DateFormatter().string(from: clock.now)
                },
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
                heartbeatOperationLease: heartbeatRuntimeOperationLease,
                releaseOperationLease: releaseRuntimeOperationLease,
                log: log
            )
        )
    }

    private func acquireRuntimeOperationLease(_ operation: RuntimeOperation) throws -> RuntimeOperationLeaseDocument {
        let document = makeRuntimeOperationLeaseDocument(operation)
        try runtimeOperationLeaseOwner().acquire(document)
        return document
    }

    func makeRuntimeOperationLeaseDocument(_ operation: RuntimeOperation) -> RuntimeOperationLeaseDocument {
        makeRuntimeOperationLeaseDocument(operation, now: clock.now)
    }

    func makeRuntimeOperationLeaseDocument(
        _ operation: RuntimeOperation,
        now: Date
    ) -> RuntimeOperationLeaseDocument {
        let timestamps = runtimeOperationLeaseTimestamps(now: now)
        return RuntimeOperationLeaseDocument(
            operationId: UUID().uuidString,
            operation: operation,
            ownerPID: Int(ProcessInfo.processInfo.processIdentifier),
            startedAt: timestamps.now,
            heartbeatAt: timestamps.now,
            expiresAt: timestamps.expiresAt,
            message: nil
        )
    }

    private func heartbeatRuntimeOperationLease(_ document: RuntimeOperationLeaseDocument) throws {
        let timestamps = runtimeOperationLeaseTimestamps(now: clock.now)
        try runtimeOperationLeaseOwner().heartbeat(
            operationId: document.operationId,
            heartbeatAt: timestamps.now,
            expiresAt: timestamps.expiresAt
        )
    }

    private func runtimeOperationLeaseTimestamps(now: Date) -> (now: String, expiresAt: String) {
        let expiresAt = now.addingTimeInterval(Constants.Runtime.runtimeOperationLeaseDurationSeconds)
        return (
            now: ISO8601DateFormatter().string(from: now),
            expiresAt: ISO8601DateFormatter().string(from: expiresAt)
        )
    }

    private func releaseRuntimeOperationLease(_ document: RuntimeOperationLeaseDocument) throws {
        try runtimeOperationLeaseOwner().release(operationId: document.operationId)
    }

    private func runtimeWorkflowOperationStateRepository() -> any RuntimeWorkflowOperationStateRepository {
        SQLiteRuntimeWorkflowOperationStateRepository(
            databaseURL: installedPaths.runtimeStateDatabase
        )
    }
}
