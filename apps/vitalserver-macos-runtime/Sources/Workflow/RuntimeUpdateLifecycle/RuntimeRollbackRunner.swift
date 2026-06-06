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
        log("rollback started backup=\(preflight.backup.path)")
        try writeStatus(.recovering, .rollback, "rollback started")

        let plan = useCase.planRollback(for: preflight)
        try RuntimeOperationPlanRunner.run(
            plan: plan.operationPlan,
            status: .recovering,
            execute: { step in
                try executeStep(step, preflight)
            },
            publish: { event in
                log("step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)")
                writeRuntimeProgressBestEffort(event, writeProgress: writeProgress, log: log)
            }
        )

        try writeStatus(.healthy, .rollback, "rollback completed")
        log("rollback restored backup=\(preflight.backup.path)")
        log("mutable VM disk preserved path=\(vmDiskPath())")
    }
}
