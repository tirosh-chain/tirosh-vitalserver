import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackRunner<RollbackCommand> {
    public var preparePreflight: (RollbackCommand) throws -> RollbackPreflightContext
    public var executeStep: (RuntimeWorkflowStep, RollbackPreflightContext) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public var vmDiskPath: () -> String
    public var log: (String) -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        preparePreflight: @escaping (RollbackCommand) throws -> RollbackPreflightContext,
        executeStep: @escaping (RuntimeWorkflowStep, RollbackPreflightContext) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        vmDiskPath: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.preparePreflight = preparePreflight
        self.executeStep = executeStep
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
        self.vmDiskPath = vmDiskPath
        self.log = log
    }

    public func run(_ command: RollbackCommand) throws {
        let preflight = try preparePreflight(command)
        let startedPlan = useCase.rollbackStartedPlan(backupPath: preflight.backup.path)
        log(startedPlan.logMessage)
        try writeStatus(startedPlan.status, startedPlan.operation, startedPlan.statusMessage)

        let plan = useCase.planRollback(for: preflight)
        try RuntimeOperationPlanRunner.run(
            plan: plan.operationPlan,
            status: .recovering,
            execute: { step in
                try executeStep(step, preflight)
            },
            publish: { event in
                log(useCase.rollbackProgressLogMessage(event: event))
                writeRuntimeProgressBestEffort(event, writeProgress: writeProgress, log: log)
            }
        )

        let completedPlan = useCase.rollbackCompletedPlan(
            backupPath: preflight.backup.path,
            vmDiskPath: vmDiskPath()
        )
        try writeStatus(
            completedPlan.statusPlan.status,
            completedPlan.statusPlan.operation,
            completedPlan.statusPlan.message
        )
        log(completedPlan.restoredBackupLogMessage)
        log(completedPlan.preservedVMDiskLogMessage)
    }
}
