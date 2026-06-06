import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestActivationWorkflowContext {
    public let guestRunDirectory: URL
    public let waitTimeoutSeconds: Double

    public init(
        guestRunDirectory: URL,
        waitTimeoutSeconds: Double
    ) {
        self.guestRunDirectory = guestRunDirectory
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }
}

public struct RuntimeGuestActivationWorkflowOperations {
    public let executeGuestActivationPlan: (
        RuntimeGuestActivationExecutionPlan,
        RuntimeGuestActivationWorkflowContext
    ) throws -> Void

    public init(
        executeGuestActivationPlan: @escaping (
            RuntimeGuestActivationExecutionPlan,
            RuntimeGuestActivationWorkflowContext
        ) throws -> Void
    ) {
        self.executeGuestActivationPlan = executeGuestActivationPlan
    }
}

public struct RuntimeGuestActivationWorkflow {
    public let context: RuntimeGuestActivationWorkflowContext
    public let operations: RuntimeGuestActivationWorkflowOperations

    public init(
        context: RuntimeGuestActivationWorkflowContext,
        operations: RuntimeGuestActivationWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        try runner().activateIfNeeded(manifest: manifest)
    }

    private func runner() -> RuntimeGuestActivationRunner {
        RuntimeGuestActivationRunner(
            executeActivationPlan: { plan in
                try operations.executeGuestActivationPlan(plan, context)
            }
        )
    }
}
