import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackStepExecutionContext {
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

public struct RuntimeRollbackStepExecutor {
    public var planStepExecution: (
        RuntimeWorkflowStep,
        RollbackPreflightContext,
        RuntimeRollbackStepExecutionContext
    ) -> RollbackRuntimeStepExecutionPlan
    public var executeStepPlan: (RollbackRuntimeStepExecutionPlan) throws -> Void

    public init(
        planStepExecution: @escaping (
            RuntimeWorkflowStep,
            RollbackPreflightContext,
            RuntimeRollbackStepExecutionContext
        ) -> RollbackRuntimeStepExecutionPlan,
        executeStepPlan: @escaping (RollbackRuntimeStepExecutionPlan) throws -> Void
    ) {
        self.planStepExecution = planStepExecution
        self.executeStepPlan = executeStepPlan
    }

    public func execute(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        rootfsBase: URL,
        runtimeVersion: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) throws {
        let executionPlan = planStepExecution(
            step,
            preflight,
            RuntimeRollbackStepExecutionContext(
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory
            )
        )

        try executeStepPlan(executionPlan)
    }
}
