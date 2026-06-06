import Contracts
import Domain
import Foundation
import Errors

public struct RollbackRuntimeExecutionContext: Equatable, Sendable {
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

public struct RollbackRuntimeStepExecutionContext: Equatable, Sendable {
    public let rootfsBase: URL
    public let runtimeVersion: URL
    public let managerAppPath: URL
    public let nginxDirectory: URL
    public let deployDirectory: URL

    public init(
        rootfsBase: URL,
        runtimeVersion: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) {
        self.rootfsBase = rootfsBase
        self.runtimeVersion = runtimeVersion
        self.managerAppPath = managerAppPath
        self.nginxDirectory = nginxDirectory
        self.deployDirectory = deployDirectory
    }
}

public struct RollbackRuntimeOperations {
    public let resolveBackupSelection: (RollbackRuntimeBackupSelection) throws -> URL
    public let observeBackupDirectory: (URL) -> RollbackRuntimeBackupDirectoryObservation
    public let loadBackupManifest: (URL) throws -> BackupManifest
    public let observeBackupRootfs: (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsObservation
    public let serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public let observeStepRequiredInput: (
        RuntimeWorkflowStep,
        RollbackPreflightContext,
        RollbackRuntimeStepRequiredInput
    ) -> RollbackRuntimeStepRequiredInputObservation
    public let executeRollbackStepPlan: (RollbackRuntimeStepExecutionPlan) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public let log: (String) -> Void

    public init(
        resolveBackupSelection: @escaping (RollbackRuntimeBackupSelection) throws -> URL,
        observeBackupDirectory: @escaping (URL) -> RollbackRuntimeBackupDirectoryObservation,
        loadBackupManifest: @escaping (URL) throws -> BackupManifest,
        observeBackupRootfs: @escaping (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsObservation,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        observeStepRequiredInput: @escaping (
            RuntimeWorkflowStep,
            RollbackPreflightContext,
            RollbackRuntimeStepRequiredInput
        ) -> RollbackRuntimeStepRequiredInputObservation,
        executeRollbackStepPlan: @escaping (RollbackRuntimeStepExecutionPlan) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.resolveBackupSelection = resolveBackupSelection
        self.observeBackupDirectory = observeBackupDirectory
        self.loadBackupManifest = loadBackupManifest
        self.observeBackupRootfs = observeBackupRootfs
        self.serviceRestartPolicy = serviceRestartPolicy
        self.observeStepRequiredInput = observeStepRequiredInput
        self.executeRollbackStepPlan = executeRollbackStepPlan
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
        self.log = log
    }
}

public struct RollbackRuntimeUseCase {
    public init() {}

    public func run(
        _ command: RuntimeRollbackCommand,
        context: RollbackRuntimeExecutionContext,
        operations: RollbackRuntimeOperations
    ) throws {
        let useCase = UpdateRuntimeUseCase()
        let preflight = try preparePreflight(command, operations: operations, useCase: useCase)
        let startedPlan = useCase.rollbackStartedPlan(backupPath: preflight.backup.path)
        operations.log(startedPlan.logMessage)
        try operations.writeStatus(startedPlan.status, startedPlan.operation, startedPlan.statusMessage)

        let plan = useCase.planRollback(for: preflight)
        try RuntimeOperationPlanRunner.run(
            plan: plan.operationPlan,
            status: .recovering,
            execute: { step in
                try executeStep(
                    step,
                    preflight: preflight,
                    context: context.stepContext,
                    operations: operations,
                    useCase: useCase
                )
            },
            publish: { event in
                operations.log(useCase.rollbackProgressLogMessage(event: event))
                writeProgressBestEffort(event, operations: operations)
            }
        )

        let completedPlan = useCase.rollbackCompletedPlan(
            backupPath: preflight.backup.path,
            vmDiskPath: context.vmDisk.path
        )
        try operations.writeStatus(
            completedPlan.statusPlan.status,
            completedPlan.statusPlan.operation,
            completedPlan.statusPlan.message
        )
        operations.log(completedPlan.restoredBackupLogMessage)
        operations.log(completedPlan.preservedVMDiskLogMessage)
    }

    public func preparePreflight(
        _ command: RuntimeRollbackCommand,
        operations: RollbackRuntimeOperations
    ) throws -> RollbackPreflightContext {
        try preparePreflight(command, operations: operations, useCase: UpdateRuntimeUseCase())
    }

    public func executeStep(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        context: RollbackRuntimeStepExecutionContext,
        operations: RollbackRuntimeOperations
    ) throws {
        try executeStep(step, preflight: preflight, context: context, operations: operations, useCase: UpdateRuntimeUseCase())
    }

    private func preparePreflight(
        _ command: RuntimeRollbackCommand,
        operations: RollbackRuntimeOperations,
        useCase: UpdateRuntimeUseCase
    ) throws -> RollbackPreflightContext {
        let backup = try operations.resolveBackupSelection(useCase.rollbackBackupSelection(command: command))
        let manifestBackup = try executeBackupDirectoryDecision(
            useCase.rollbackBackupDirectoryDecision(observation: operations.observeBackupDirectory(backup))
        )
        let manifest = try operations.loadBackupManifest(manifestBackup)
        let backupPlan = useCase.rollbackBackupPlan(backup: backup, manifest: manifest)
        let resolvedBackupPlan = try executeBackupRootfsDecision(
            useCase.rollbackBackupRootfsDecision(observation: operations.observeBackupRootfs(backupPlan))
        )

        let restartPolicy = operations.serviceRestartPolicy()
        let preflightPlan = useCase.rollbackPreflightPlan(backup: backup, restartPolicy: restartPolicy)
        operations.log(preflightPlan.serviceRestartLogMessage)

        return RollbackPreflightContext(
            backup: resolvedBackupPlan.backup,
            backupRootfs: resolvedBackupPlan.backupRootfs,
            backupVersion: resolvedBackupPlan.backupVersion,
            restoresRootfsBase: resolvedBackupPlan.restoresRootfsBase,
            restartPolicy: restartPolicy
        )
    }

    private func executeStep(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        context: RollbackRuntimeStepExecutionContext,
        operations: RollbackRuntimeOperations,
        useCase: UpdateRuntimeUseCase
    ) throws {
        let requiredInput = useCase.rollbackStepRequiredInput(step: step, preflight: preflight)
        let executionPlan = useCase.rollbackStepExecutionPlan(
            step: step,
            preflight: preflight,
            rootfsBase: context.rootfsBase,
            runtimeVersion: context.runtimeVersion,
            managerAppPath: context.managerAppPath,
            nginxDirectory: context.nginxDirectory,
            deployDirectory: context.deployDirectory,
            observation: operations.observeStepRequiredInput(step, preflight, requiredInput)
        )
        try operations.executeRollbackStepPlan(executionPlan)
    }

    private func executeBackupDirectoryDecision(
        _ decision: RollbackRuntimeBackupDirectoryDecision
    ) throws -> URL {
        switch decision {
        case .loadManifest(let backup):
            return backup
        case .failed(let message):
            throw RollbackRuntimeUseCaseError.operationFailed(message)
        }
    }

    private func executeBackupRootfsDecision(
        _ decision: RollbackRuntimeBackupRootfsDecision
    ) throws -> RollbackRuntimeBackupPlan {
        switch decision {
        case .proceed(let plan):
            return plan
        case .failed(let message):
            throw RollbackRuntimeUseCaseError.operationFailed(message)
        }
    }

    private func writeProgressBestEffort(
        _ event: RuntimeStepExecutionEvent,
        operations: RollbackRuntimeOperations
    ) {
        do {
            try operations.writeProgress(event)
        } catch {
            operations.log(RuntimeWorkflowUseCase().progressWriteFailedLogMessage(
                event: event,
                reason: RuntimeErrorDescription.describe(error)
            ))
        }
    }
}

private extension RollbackRuntimeExecutionContext {
    var stepContext: RollbackRuntimeStepExecutionContext {
        RollbackRuntimeStepExecutionContext(
            rootfsBase: rootfsBase,
            runtimeVersion: runtimeVersion,
            managerAppPath: managerAppPath,
            nginxDirectory: nginxDirectory,
            deployDirectory: deployDirectory
        )
    }
}
