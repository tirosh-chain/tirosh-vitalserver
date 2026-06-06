import Application
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
        self.log = log
    }
}

public enum RuntimeRollbackComposition {
    public static func make(
        context: RuntimeRollbackCompositionContext,
        operations: RuntimeRollbackCompositionOperations
    ) -> RuntimeRollbackWorkflow {
        RuntimeRollbackWorkflow(
            context: RuntimeRollbackWorkflowContext(
                rootfsBase: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
                runtimeVersion: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion),
                vmDisk: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
                managerAppPath: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxDirectory: context.installedPaths.nginxDirectory,
                deployDirectory: context.installedPaths.deployDirectory
            ),
            operations: RuntimeRollbackWorkflowOperations(
                resolveBackupSelection: { selection in
                    switch selection {
                    case .latestBackup:
                        return try operations.requireLatestBackup()
                    case .specificBackup(let backup):
                        return backup
                    }
                },
                resolveBackupDirectory: { backup in
                    try executeBackupDirectoryDecision(UpdateRuntimeUseCase().rollbackBackupDirectoryDecision(
                        observation: RollbackRuntimeBackupDirectoryObservation(
                            backup: backup,
                            directoryExists: operations.fileStore.directoryExists(backup)
                        )
                    ))
                },
                resolveBackupRootfs: { backupPlan in
                    try executeBackupRootfsDecision(UpdateRuntimeUseCase().rollbackBackupRootfsDecision(
                        observation: RollbackRuntimeBackupRootfsObservation(
                            backupPlan: backupPlan,
                            backupRootfsExists: backupPlan.backupRootfs.map(operations.fileStore.fileExists)
                        )
                    ))
                },
                loadBackupManifest: RuntimeBackupManifestLoader(fileStore: operations.fileStore).load,
                isLaunchdLoaded: operations.isLaunchdLoaded,
                planRollbackStepExecution: { step, preflight, stepContext in
                    let useCase = UpdateRuntimeUseCase()
                    let requiredInput = useCase.rollbackStepRequiredInput(step: step, preflight: preflight)
                    return useCase.rollbackStepExecutionPlan(
                        step: step,
                        preflight: preflight,
                        rootfsBase: stepContext.rootfsBase,
                        runtimeVersion: stepContext.runtimeVersion,
                        managerAppPath: stepContext.managerAppPath,
                        nginxDirectory: stepContext.nginxDirectory,
                        deployDirectory: stepContext.deployDirectory,
                        observation: rollbackStepRequiredInputObservation(
                            requiredInput: requiredInput,
                            fileStore: operations.fileStore
                        )
                    )
                },
                executeRollbackStepPlan: { plan in
                    try executeRollbackStepPlan(plan, operations: operations)
                },
                writeStatus: operations.writeStatus,
                writeProgress: operations.writeProgress,
                log: operations.log
            )
        )
    }

    private static func rollbackStepRequiredInputObservation(
        requiredInput: RollbackRuntimeStepRequiredInput,
        fileStore: RuntimeFileStore
    ) -> RollbackRuntimeStepRequiredInputObservation {
        switch requiredInput {
        case .none:
            return RollbackRuntimeStepRequiredInputObservation(
                requiredInput: requiredInput,
                backupVersionExists: false
            )
        case .backupVersionExists(let backupVersion):
            return RollbackRuntimeStepRequiredInputObservation(
                requiredInput: requiredInput,
                backupVersionExists: fileStore.fileExists(backupVersion)
            )
        }
    }

    private static func executeBackupDirectoryDecision(
        _ decision: RollbackRuntimeBackupDirectoryDecision
    ) throws -> URL {
        switch decision {
        case .loadManifest(let backup):
            return backup
        case .failed(let message):
            throw RuntimeRollbackWorkflowError.operationFailed(message)
        }
    }

    private static func executeBackupRootfsDecision(
        _ decision: RollbackRuntimeBackupRootfsDecision
    ) throws -> RollbackRuntimeBackupPlan {
        switch decision {
        case .proceed(let plan):
            return plan
        case .failed(let message):
            throw RuntimeRollbackWorkflowError.operationFailed(message)
        }
    }

    private static func executeRollbackStepPlan(
        _ plan: RollbackRuntimeStepExecutionPlan,
        operations: RuntimeRollbackCompositionOperations
    ) throws {
        switch plan {
        case .stopRuntimeServices:
            try operations.stopRuntimeServices()
        case .restoreRootfsBase(let source, let destination):
            try operations.replaceFile(source, destination)
        case .restoreRuntimeVersion(let decision):
            try executeRollbackVersionRestoreDecision(decision, operations: operations)
        case .restoreUpdateArtifacts(let restorePlan):
            for artifact in restorePlan.directoryRestores {
                try operations.restoreBackupPathIfExists(
                    artifact.backupPath,
                    artifact.restoreDestination
                )
            }
            try operations.restoreRuntimeToolsIfExists(restorePlan.runtimeToolsBackup)
        case .startRuntimeServices(let restartPolicy):
            try operations.startRuntimeServices(restartPolicy)
        case .waitRuntimeHealth(let restartPolicy):
            try operations.waitForHealth(restartPolicy)
        case .failed(let failureMessage), .unsupported(let failureMessage):
            throw RuntimeRollbackWorkflowError.operationFailed(failureMessage)
        }
    }

    private static func executeRollbackVersionRestoreDecision(
        _ decision: RollbackRuntimeVersionRestoreDecision,
        operations: RuntimeRollbackCompositionOperations
    ) throws {
        switch decision {
        case .restoreBackupVersion(let source, let destination):
            try operations.replaceFile(source, destination)
        case .writeExplicitRollbackMarker(let version, let destinationDirectory):
            try operations.writeRuntimeVersion(version, destinationDirectory)
        }
    }
}
