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

public struct RuntimeRollbackComposition {
    let context: RuntimeRollbackCompositionContext
    let operations: RuntimeRollbackCompositionOperations

    public static func make(
        context: RuntimeRollbackCompositionContext,
        operations: RuntimeRollbackCompositionOperations
    ) -> RuntimeRollbackComposition {
        RuntimeRollbackComposition(context: context, operations: operations)
    }

    public func rollback(_ command: RuntimeRollbackCommand) throws {
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
                        directoryExists: operations.fileStore.directoryExists(backup)
                    )
                },
                loadBackupManifest: RuntimeBackupManifestLoader(fileStore: operations.fileStore).load,
                observeBackupRootfs: { backupPlan in
                    RollbackRuntimeBackupRootfsObservation(
                        backupPlan: backupPlan,
                        backupRootfsExists: backupPlan.backupRootfs.map(operations.fileStore.fileExists)
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
                writeProgress: operations.writeProgress,
                describeError: RuntimeErrorDescription.describe,
                log: operations.log
            )
        )
    }

    private func serviceRestartPolicy() -> RuntimeServiceRestartPolicy {
        RuntimeServiceRestartPolicy(
            restartVM: operations.isLaunchdLoaded(.vm),
            restartGuestLogSync: operations.isLaunchdLoaded(.guestLogSync),
            restartProxy: operations.isLaunchdLoaded(.proxy),
            restartWatchdog: operations.isLaunchdLoaded(.watchdog)
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
                backupVersionExists: false
            )
        case .backupVersionExists(let backupVersion):
            return RollbackRuntimeStepRequiredInputObservation(
                requiredInput: requiredInput,
                backupVersionExists: fileStore.fileExists(backupVersion)
            )
        }
    }
}
