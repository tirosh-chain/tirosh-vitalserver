import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackWorkflowContext {
    public let rootfsBase: URL
    public let runtimeVersion: URL
    public let vmDisk: URL
    public let managerAppPath: URL
    public let nginxDirectory: URL
    public let deployDirectory: URL

    public init(
        rootfsBase: URL,
        runtimeVersion: URL,
        vmDisk: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) {
        self.rootfsBase = rootfsBase
        self.runtimeVersion = runtimeVersion
        self.vmDisk = vmDisk
        self.managerAppPath = managerAppPath
        self.nginxDirectory = nginxDirectory
        self.deployDirectory = deployDirectory
    }
}

public struct RuntimeRollbackWorkflowOperations {
    public let resolveBackupSelection: (RollbackRuntimeBackupSelection) throws -> URL
    public let observeBackupDirectory: (URL) -> RollbackRuntimeBackupDirectoryObservation
    public let observeBackupRootfs: (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsObservation
    public let observeRequiredInput: (RollbackRuntimeStepRequiredInput) -> RollbackRuntimeStepRequiredInputObservation
    public let loadBackupManifest: (URL) throws -> BackupManifest
    public let isLaunchdLoaded: (RuntimeManagedService) -> Bool
    public let stopRuntimeServices: () throws -> Void
    public let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let replaceFile: (URL, URL) throws -> Void
    public let writeRuntimeVersion: (String, URL) throws -> Void
    public let restoreBackupPathIfExists: (URL, URL) throws -> Void
    public let restoreRuntimeToolsIfExists: (URL) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public let log: (String) -> Void

    public init(
        resolveBackupSelection: @escaping (RollbackRuntimeBackupSelection) throws -> URL,
        observeBackupDirectory: @escaping (URL) -> RollbackRuntimeBackupDirectoryObservation,
        observeBackupRootfs: @escaping (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsObservation,
        observeRequiredInput: @escaping (RollbackRuntimeStepRequiredInput) -> RollbackRuntimeStepRequiredInputObservation,
        loadBackupManifest: @escaping (URL) throws -> BackupManifest,
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
        self.resolveBackupSelection = resolveBackupSelection
        self.observeBackupDirectory = observeBackupDirectory
        self.observeBackupRootfs = observeBackupRootfs
        self.observeRequiredInput = observeRequiredInput
        self.loadBackupManifest = loadBackupManifest
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

public struct RuntimeRollbackWorkflow {
    public let context: RuntimeRollbackWorkflowContext
    public let operations: RuntimeRollbackWorkflowOperations

    public init(
        context: RuntimeRollbackWorkflowContext,
        operations: RuntimeRollbackWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackRunner().run(command)
    }

    private func runtimeRollbackRunner() -> RuntimeRollbackRunner<RuntimeRollbackCommand> {
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
        return try RuntimeRollbackPreflightRunner(
            resolveBackupSelection: operations.resolveBackupSelection,
            observeBackupDirectory: operations.observeBackupDirectory,
            observeBackupRootfs: operations.observeBackupRootfs,
            loadManifest: operations.loadBackupManifest,
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
            observeRequiredInput: operations.observeRequiredInput,
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
