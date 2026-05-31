import Foundation
import Core
import Contracts

struct RuntimeRollbackRunner {
    var preparePreflight: (RuntimeRollbackCommand) throws -> RollbackPreflightContext
    var executeStep: (RuntimeWorkflowStep, RollbackPreflightContext) throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    var vmDiskPath: () -> String
    var log: (String) -> Void

    func run(_ command: RuntimeRollbackCommand) throws {
        let preflight = try preparePreflight(command)
        log("rollback started backup=\(preflight.backup.path)")
        try writeStatus(.recovering, .rollback, "rollback started")

        try RuntimeOperationPlanRunner.run(
            plan: RuntimeOperationPlans.rollback(restoresRootfsBase: preflight.restoresRootfsBase),
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
