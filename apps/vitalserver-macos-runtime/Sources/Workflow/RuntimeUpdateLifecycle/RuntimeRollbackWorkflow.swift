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
    public let resolveBackupDirectory: (URL) throws -> URL
    public let resolveBackupRootfs: (RollbackRuntimeBackupPlan) throws -> RollbackRuntimeBackupPlan
    public let loadBackupManifest: (URL) throws -> BackupManifest
    public let isLaunchdLoaded: (RuntimeManagedService) -> Bool
    public let planRollbackStepExecution: (
        RuntimeWorkflowStep,
        RollbackPreflightContext,
        RuntimeRollbackStepExecutionContext
    ) -> RollbackRuntimeStepExecutionPlan
    public let executeRollbackStepPlan: (RollbackRuntimeStepExecutionPlan) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public let log: (String) -> Void

    public init(
        resolveBackupSelection: @escaping (RollbackRuntimeBackupSelection) throws -> URL,
        resolveBackupDirectory: @escaping (URL) throws -> URL,
        resolveBackupRootfs: @escaping (RollbackRuntimeBackupPlan) throws -> RollbackRuntimeBackupPlan,
        loadBackupManifest: @escaping (URL) throws -> BackupManifest,
        isLaunchdLoaded: @escaping (RuntimeManagedService) -> Bool,
        planRollbackStepExecution: @escaping (
            RuntimeWorkflowStep,
            RollbackPreflightContext,
            RuntimeRollbackStepExecutionContext
        ) -> RollbackRuntimeStepExecutionPlan,
        executeRollbackStepPlan: @escaping (RollbackRuntimeStepExecutionPlan) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.resolveBackupSelection = resolveBackupSelection
        self.resolveBackupDirectory = resolveBackupDirectory
        self.resolveBackupRootfs = resolveBackupRootfs
        self.loadBackupManifest = loadBackupManifest
        self.isLaunchdLoaded = isLaunchdLoaded
        self.planRollbackStepExecution = planRollbackStepExecution
        self.executeRollbackStepPlan = executeRollbackStepPlan
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
            resolveBackupDirectory: operations.resolveBackupDirectory,
            resolveBackupRootfs: operations.resolveBackupRootfs,
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
            planStepExecution: operations.planRollbackStepExecution,
            executeStepPlan: operations.executeRollbackStepPlan
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
