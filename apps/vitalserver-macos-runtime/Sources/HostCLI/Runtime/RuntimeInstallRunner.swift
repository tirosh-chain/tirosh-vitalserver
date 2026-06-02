import Core
import Contracts

struct RuntimeInstallRunner {
    var plan: RuntimeOperationPlan = RuntimeOperationPlans.install
    var completionStatus: RuntimeStatusLevel = .healthy
    var completionMessage: String = "runtime install completed"
    var loadSettings: () throws -> InstallSettings
    var executeStep: (RuntimeWorkflowStep, InstallSettings) throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    var runtimeHomePath: () -> String
    var log: (String) -> Void

    func run() throws {
        let settings = try loadSettings()
        log("runtime install started home=\(runtimeHomePath())")
        try writeStatus(.installing, .install, "runtime install started")
        do {
            try RuntimeOperationPlanRunner.run(
                plan: plan,
                status: .installing,
                execute: { step in
                    try executeStep(step, settings)
                },
                publish: { event in
                    log("step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)")
                    writeRuntimeProgressBestEffort(event, writeProgress: writeProgress, log: log)
                }
            )
            try writeStatus(completionStatus, .install, completionMessage)
            log("\(completionMessage) home=\(runtimeHomePath())")
        } catch {
            writeRuntimeStatusBestEffort(
                .critical,
                operation: .install,
                message: "runtime install failed: \(error)",
                writeStatus: writeStatus,
                log: log
            )
            throw error
        }
    }
}
