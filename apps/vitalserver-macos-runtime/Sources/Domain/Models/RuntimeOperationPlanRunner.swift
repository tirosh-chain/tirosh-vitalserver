import Contracts

public enum RuntimeOperationPlanRunner {
    public static func run(
        plan: RuntimeOperationPlan,
        status: RuntimeStatusLevel,
        execute: (RuntimeWorkflowStep) throws -> Void,
        publish: (RuntimeStepExecutionEvent) -> Void
    ) throws {
        let invalidSteps = plan.invalidSteps
        guard invalidSteps.isEmpty else {
            throw RuntimeOperationPlanValidationError(
                operation: plan.operation,
                invalidSteps: invalidSteps
            )
        }

        for step in plan.steps {
            publish(event(
                plan: plan,
                status: status,
                step: step,
                stepStatus: .started,
                phase: .running,
                message: "step started: \(step.rawValue)"
            ))
            do {
                try execute(step)
                publish(event(
                    plan: plan,
                    status: status,
                    step: step,
                    stepStatus: .completed,
                    phase: .running,
                    message: "step completed: \(step.rawValue)"
                ))
            } catch {
                publish(event(
                    plan: plan,
                    status: status,
                    step: step,
                    stepStatus: .failed,
                    phase: .failed,
                    message: "step failed: \(step.rawValue): \(error)"
                ))
                throw error
            }
        }
    }

    private static func event(
        plan: RuntimeOperationPlan,
        status: RuntimeStatusLevel,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String
    ) -> RuntimeStepExecutionEvent {
        RuntimeStepExecutionEvent(
            operation: plan.operation,
            status: status,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message
        )
    }
}
