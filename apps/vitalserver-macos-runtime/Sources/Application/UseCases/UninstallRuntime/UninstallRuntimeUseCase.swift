import Foundation
import Domain
import Errors

public struct UninstallRuntimeUseCase {
    public init() {}

    public func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommands: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: state,
            event: event
        )
        try requireCommands(expectedCommands, in: decision)
        return decision
    }

    public func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommandsWhenAllowed: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: state,
            event: event
        )
        try requireCommands(
            decision.blockers.isEmpty ? expectedCommandsWhenAllowed : [],
            in: decision
        )
        return decision
    }

    public func requireCommands(
        _ expectedCommands: [RuntimeUninstallWorkflowCommand],
        in decision: RuntimeUninstallTransitionDecision
    ) throws {
        guard decision.commands == expectedCommands else {
            throw UninstallRuntimeUseCaseError.operationFailed(
                "unexpected uninstall workflow commands state=\(decision.state) expected=\(expectedCommands) actual=\(decision.commands)"
            )
        }
    }
}
