import Foundation
import Contracts
import Domain
import Errors

public struct InstallRuntimeRequest: Equatable, Sendable {
    public let mode: RuntimeInstallMode

    public init(
        mode: RuntimeInstallMode
    ) {
        self.mode = mode
    }
}

public struct InstallRuntimePlan: Equatable, Sendable {
    public let mode: RuntimeInstallMode
    public let operationPlan: RuntimeOperationPlan
    public let completionStatus: RuntimeStatusLevel
    public let completionMessage: String

    public init(
        mode: RuntimeInstallMode,
        operationPlan: RuntimeOperationPlan,
        completionStatus: RuntimeStatusLevel,
        completionMessage: String
    ) {
        self.mode = mode
        self.operationPlan = operationPlan
        self.completionStatus = completionStatus
        self.completionMessage = completionMessage
    }
}

public struct InstallRuntimeUseCase {
    public init() {}

    public func plan(for request: InstallRuntimeRequest) -> InstallRuntimePlan {
        switch request.mode {
        case .full:
            return InstallRuntimePlan(
                mode: .full,
                operationPlan: RuntimeOperationPlans.install,
                completionStatus: .healthy,
                completionMessage: "runtime install completed"
            )
        case .provision:
            return InstallRuntimePlan(
                mode: .provision,
                operationPlan: RuntimeOperationPlans.installProvision,
                completionStatus: .degraded,
                completionMessage: "runtime install provisioned; runtime services starting"
            )
        case .unknown:
            return InstallRuntimePlan(
                mode: request.mode,
                operationPlan: RuntimeOperationPlans.install,
                completionStatus: .critical,
                completionMessage: "runtime install failed"
            )
        }
    }

    public func transition(
        from state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        context: RuntimeInstallTransitionContext,
        expectedCommands: [RuntimeInstallWorkflowCommand]? = nil
    ) throws -> RuntimeInstallTransitionDecision {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: state,
            event: event,
            context: context
        )
        if let expectedCommands {
            try requireCommands(expectedCommands, in: decision)
        }
        return decision
    }

    public func setupReadCommands(for plan: InstallRuntimePlan) throws -> [RuntimeInstallWorkflowCommand] {
        switch plan.mode {
        case .full:
            return [.readFreshInstallPreflight]
        case .provision:
            return [.readProvisionPayload]
        case .unknown(let value):
            throw InstallRuntimeUseCaseError.operationFailed("install mode unknown value=\(value)")
        }
    }

    public func expectedCommandsAfterFreshInstallPreflight(
        _ document: RuntimeFreshInstallPreflightDocument,
        plan: InstallRuntimePlan
    ) throws -> [RuntimeInstallWorkflowCommand] {
        guard plan.mode == .full else {
            throw InstallRuntimeUseCaseError.operationFailed("provision install must not use fresh install preflight")
        }
        guard document.passed, document.blockers.isEmpty else {
            return []
        }
        return firstStepCommand(plan.operationPlan)
    }

    public func expectedCommandsAfterProvisionPayload(
        _ document: RuntimeInstallProvisionPayloadDocument,
        plan: InstallRuntimePlan
    ) throws -> [RuntimeInstallWorkflowCommand] {
        guard plan.mode == .provision else {
            throw InstallRuntimeUseCaseError.operationFailed("full install must use fresh install preflight")
        }
        guard document.passed, document.blockers.isEmpty else {
            return []
        }
        return firstStepCommand(plan.operationPlan)
    }

    public func requireCommands(
        _ expectedCommands: [RuntimeInstallWorkflowCommand],
        in decision: RuntimeInstallTransitionDecision
    ) throws {
        guard decision.commands == expectedCommands else {
            throw InstallRuntimeUseCaseError.operationFailed(
                "unexpected install workflow commands state=\(decision.state) expected=\(expectedCommands) actual=\(decision.commands)"
            )
        }
    }

    private func firstStepCommand(_ plan: RuntimeOperationPlan) -> [RuntimeInstallWorkflowCommand] {
        guard let firstStep = plan.steps.first else {
            return [.complete]
        }
        return [.executeStep(firstStep)]
    }
}
