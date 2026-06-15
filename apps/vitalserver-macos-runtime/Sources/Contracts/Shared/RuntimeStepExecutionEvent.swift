public struct RuntimeStepExecutionEvent: Equatable, Sendable {
    public let operation: RuntimeOperation
    public let status: RuntimeStatusLevel
    public let step: RuntimeWorkflowStep
    public let stepStatus: RuntimeProgressStepStatus
    public let phase: RuntimeProgressPhase
    public let message: String

    public init(
        operation: RuntimeOperation,
        status: RuntimeStatusLevel,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String
    ) {
        self.operation = operation
        self.status = status
        self.step = step
        self.stepStatus = stepStatus
        self.phase = phase
        self.message = message
    }
}
