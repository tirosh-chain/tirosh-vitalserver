import Foundation
import Core
import Contracts
import RuntimeWorkflow

struct RuntimeRollbackWorkflowContext {
    let rootfsBase: URL
    let runtimeVersion: URL
    let vmDisk: URL
    let managerAppPath: URL
    let nginxDirectory: URL
    let deployDirectory: URL
}

struct RuntimeRollbackWorkflowOperations {
    let requireLatestBackup: () throws -> URL
    let directoryExists: (URL) -> Bool
    let fileExists: (URL) -> Bool
    let readData: (URL) throws -> Data
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
}

struct RuntimeRollbackWorkflow {
    let context: RuntimeRollbackWorkflowContext
    let operations: RuntimeRollbackWorkflowOperations

    func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackRunner().run(command)
    }

    private func runtimeRollbackRunner() -> RuntimeRollbackRunner {
        RuntimeRollbackRunner(
            preparePreflight: prepareRollbackPreflight,
            executeStep: executeRollbackStep,
            writeStatus: operations.writeStatus,
            writeProgress: operations.writeProgress,
            vmDiskPath: { context.vmDisk.path },
            log: operations.log
        )
    }

    private func prepareRollbackPreflight(_ command: RuntimeRollbackCommand) throws -> RollbackPreflightContext {
        try RuntimeRollbackPreflightRunner(
            requireLatestBackup: operations.requireLatestBackup,
            directoryExists: operations.directoryExists,
            fileExists: operations.fileExists,
            loadManifest: { backup in
                let manifestURL = backup.appendingPathComponent(Constants.Artifacts.backupManifest)
                guard operations.fileExists(manifestURL) else {
                    throw LauncherError.missingFile(manifestURL.path)
                }
                let data = try operations.readData(manifestURL)
                return try JSONDecoder().decode(BackupManifest.self, from: data)
            },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(
                    restartVM: operations.isLaunchdLoaded(.vm),
                    restartGuestLogSync: operations.isLaunchdLoaded(.guestLogSync),
                    restartProxy: operations.isLaunchdLoaded(.proxy),
                    restartWatchdog: operations.isLaunchdLoaded(.watchdog)
                )
            },
            log: operations.log
        ).prepare(command)
    }

    private func executeRollbackStep(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext
    ) throws {
        let executor = RuntimeRollbackStepExecutor(
            stopRuntimeServices: operations.stopRuntimeServices,
            replaceFile: operations.replaceFile,
            fileExists: operations.fileExists,
            writeRuntimeVersion: operations.writeRuntimeVersion,
            restoreBackupPathIfExists: operations.restoreBackupPathIfExists,
            restoreRuntimeToolsIfExists: operations.restoreRuntimeToolsIfExists,
            startRuntimeServices: operations.startRuntimeServices,
            waitForHealth: operations.waitForHealth
        )
        try executor.execute(
            step,
            preflight: preflight,
            rootfsBase: context.rootfsBase,
            runtimeVersion: context.runtimeVersion,
            managerAppPath: context.managerAppPath,
            nginxDirectory: context.nginxDirectory,
            deployDirectory: context.deployDirectory
        )
    }
}
