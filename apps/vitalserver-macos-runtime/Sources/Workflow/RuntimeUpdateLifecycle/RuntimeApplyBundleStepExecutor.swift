import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeApplyBundleStepExecutor {
    public var executeStepPlan: (ApplyRuntimeBundleStepExecutionPlan) throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        executeStepPlan: @escaping (ApplyRuntimeBundleStepExecutionPlan) throws -> Void
    ) {
        self.executeStepPlan = executeStepPlan
    }

    public func execute(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext,
        rootfsBase: URL
    ) throws {
        let executionPlan = useCase.applyBundleStepExecutionPlan(
            step: step,
            preflight: preflight,
            rootfsBase: rootfsBase
        )

        try executeStepPlan(executionPlan)
    }
}
