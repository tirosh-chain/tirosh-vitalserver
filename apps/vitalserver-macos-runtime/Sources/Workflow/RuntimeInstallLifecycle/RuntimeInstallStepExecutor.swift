import Contracts
import Application
import Domain
import Errors

public struct RuntimeInstallStepExecutor<Settings> {
    public var executeStepPlan: (InstallRuntimeStepExecutionPlan, Settings) throws -> Void

    public init(
        executeStepPlan: @escaping (InstallRuntimeStepExecutionPlan, Settings) throws -> Void
    ) {
        self.executeStepPlan = executeStepPlan
    }

    public func execute(_ step: RuntimeWorkflowStep, settings: Settings) throws {
        try executeStepPlan(InstallRuntimeUseCase().stepExecutionPlan(step), settings)
    }
}
