import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Workflow
import Errors

public struct RuntimeRollbackCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(installedPaths: InstalledRuntimePaths) {
        self.installedPaths = installedPaths
    }
}

public enum RuntimeRollbackInvocation: Equatable, Sendable {
    case standalone(operationID: String, startedAt: String)
    case applyBundleRecovery(parentOperationID: String)
}

public struct RuntimeRollbackCompositionOperations {
    let fileStore: RuntimeFileStore
    let requireLatestBackup: () throws -> URL
    let isLaunchdLoaded: (RuntimeManagedService) -> Bool
    let stopRuntimeServices: () throws -> Void
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let replaceFile: (URL, URL) throws -> Void
    let writeRuntimeVersion: (String, URL) throws -> Void
    let restoreBackupPathIfExists: (URL, URL) throws -> Void
    let restoreRuntimeToolsIfExists: (URL) throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    let workflowOperationStateRepository: any RuntimeWorkflowOperationStateRepository
    let workflowOperationStateTimestamp: () -> String
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        requireLatestBackup: @escaping () throws -> URL,
        isLaunchdLoaded: @escaping (RuntimeManagedService) -> Bool,
        stopRuntimeServices: @escaping () throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        replaceFile: @escaping (URL, URL) throws -> Void,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        restoreBackupPathIfExists: @escaping (URL, URL) throws -> Void,
        restoreRuntimeToolsIfExists: @escaping (URL) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        workflowOperationStateRepository: any RuntimeWorkflowOperationStateRepository,
        workflowOperationStateTimestamp: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.requireLatestBackup = requireLatestBackup
        self.isLaunchdLoaded = isLaunchdLoaded
        self.stopRuntimeServices = stopRuntimeServices
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
        self.replaceFile = replaceFile
        self.writeRuntimeVersion = writeRuntimeVersion
        self.restoreBackupPathIfExists = restoreBackupPathIfExists
        self.restoreRuntimeToolsIfExists = restoreRuntimeToolsIfExists
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
        self.workflowOperationStateRepository = workflowOperationStateRepository
        self.workflowOperationStateTimestamp = workflowOperationStateTimestamp
        self.log = log
    }
}

public struct RuntimeRollbackComposition {
    let context: RuntimeRollbackCompositionContext
    let operations: RuntimeRollbackCompositionOperations

    public static func make(
        context: RuntimeRollbackCompositionContext,
        operations: RuntimeRollbackCompositionOperations
    ) -> RuntimeRollbackComposition {
        RuntimeRollbackComposition(context: context, operations: operations)
    }

    public func rollback(
        _ command: RuntimeRollbackCommand,
        invocation: RuntimeRollbackInvocation
    ) throws {
        switch invocation {
        case .standalone(let operationID, let startedAt):
            try rollbackStandalone(
                command,
                operationID: operationID,
                startedAt: startedAt
            )
        case .applyBundleRecovery(let parentOperationID):
            operations.log(
                "runtime rollback executing as apply-bundle recovery parentOperationId=\(parentOperationID)"
            )
            try runWorkflow(command, writeProgress: writeDiagnosticProgress)
        }
    }

    private func rollbackStandalone(
        _ command: RuntimeRollbackCommand,
        operationID: String,
        startedAt: String
    ) throws {
        let persistence = PersistRuntimeWorkflowOperationStateUseCase()
        try persistence.start(
            repository: operations.workflowOperationStateRepository,
            operationID: operationID,
            operation: .rollback,
            message: "runtime rollback started",
            occurredAt: startedAt
        )
        do {
            try runWorkflow(command) { event in
                try persistence.record(
                    repository: operations.workflowOperationStateRepository,
                    operationID: operationID,
                    event: event,
                    occurredAt: operations.workflowOperationStateTimestamp()
                )
                writeDiagnosticProgress(event)
            }
            try persistence.complete(
                repository: operations.workflowOperationStateRepository,
                operationID: operationID,
                message: "runtime rollback completed",
                occurredAt: operations.workflowOperationStateTimestamp()
            )
        } catch {
            let operationFailure = RuntimeErrorDescription.describe(error)
            do {
                try persistence.fail(
                    repository: operations.workflowOperationStateRepository,
                    operationID: operationID,
                    message: "runtime rollback failed: \(operationFailure)",
                    reasonCodes: ["rollback-failed"],
                    occurredAt: operations.workflowOperationStateTimestamp()
                )
            } catch {
                throw RollbackRuntimeUseCaseError.operationFailed(
                    "runtime rollback failed operationId=\(operationID) operationFailure=\(operationFailure) statePersistenceFailure=\(RuntimeErrorDescription.describe(error))"
                )
            }
            throw error
        }
    }

    private func runWorkflow(
        _ command: RuntimeRollbackCommand,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void
    ) throws {
        try RollbackRuntimeWorkflow().run(
            command,
            context: RollbackRuntimeExecutionContext(
                rootfsBase: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
                runtimeVersion: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion),
                vmDisk: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
                managerAppPath: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxDirectory: context.installedPaths.nginxDirectory,
                deployDirectory: context.installedPaths.deployDirectory
            ),
            operations: RollbackRuntimeOperations(
                resolveBackupSelection: { selection in
                    switch selection {
                    case .latestBackup:
                        return try operations.requireLatestBackup()
                    case .specificBackup(let backup):
                        return backup
                    }
                },
                observeBackupDirectory: { backup in
                    RollbackRuntimeBackupDirectoryObservation(
                        backup: backup,
                        backupDirectoryState: operations.fileStore.pathState(at: backup)
                    )
                },
                loadBackupManifest: RuntimeBackupManifestLoader(fileStore: operations.fileStore).load,
                observeBackupRootfs: { backupPlan in
                    RollbackRuntimeBackupRootfsObservation(
                        backupPlan: backupPlan,
                        backupRootfsState: backupPlan.backupRootfs.map { operations.fileStore.pathState(at: $0) }
                    )
                },
                serviceRestartPolicy: serviceRestartPolicy,
                observeStepRequiredInput: { _, _, requiredInput in
                    rollbackStepRequiredInputObservation(
                        requiredInput: requiredInput,
                        fileStore: operations.fileStore
                    )
                },
                stopRuntimeServices: operations.stopRuntimeServices,
                replaceFile: operations.replaceFile,
                writeRuntimeVersion: operations.writeRuntimeVersion,
                restoreBackupPathIfExists: operations.restoreBackupPathIfExists,
                restoreRuntimeToolsIfExists: operations.restoreRuntimeToolsIfExists,
                startRuntimeServices: operations.startRuntimeServices,
                waitForHealth: operations.waitForHealth,
                writeStatus: operations.writeStatus,
                writeProgress: writeProgress,
                describeError: RuntimeErrorDescription.describe,
                log: operations.log
            )
        )
    }

    private func writeDiagnosticProgress(_ event: RuntimeStepExecutionEvent) {
        do {
            try operations.writeProgress(event)
        } catch {
            operations.log(RuntimeOperationReportingUseCase().progressWriteFailedLogMessage(
                event: event,
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
    }

    private func serviceRestartPolicy() -> RuntimeServiceRestartPolicy {
        // Rollback restores the installed runtime surface, not the transient launchd state left by a failed apply.
        RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: true,
            restartWatchdog: true
        )
    }

    private func rollbackStepRequiredInputObservation(
        requiredInput: RollbackRuntimeStepRequiredInput,
        fileStore: RuntimeFileStore
    ) -> RollbackRuntimeStepRequiredInputObservation {
        switch requiredInput {
        case .none:
            return RollbackRuntimeStepRequiredInputObservation(
                requiredInput: requiredInput,
                backupVersionState: nil
            )
        case .backupVersionExists(let backupVersion):
            return RollbackRuntimeStepRequiredInputObservation(
                requiredInput: requiredInput,
                backupVersionState: fileStore.pathState(at: backupVersion)
            )
        }
    }
}
