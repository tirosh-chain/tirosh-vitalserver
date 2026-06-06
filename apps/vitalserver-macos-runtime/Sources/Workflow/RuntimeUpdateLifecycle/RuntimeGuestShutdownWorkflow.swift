import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestShutdownWorkflowContext {
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

public struct RuntimeGuestShutdownWorkflowOperations {
    public let executeGuestShutdownPlan: (
        RuntimeGuestShutdownExecutionPlan,
        RuntimeGuestShutdownWorkflowContext
    ) throws -> Void

    public init(
        executeGuestShutdownPlan: @escaping (
            RuntimeGuestShutdownExecutionPlan,
            RuntimeGuestShutdownWorkflowContext
        ) throws -> Void
    ) {
        self.executeGuestShutdownPlan = executeGuestShutdownPlan
    }
}

public struct RuntimeGuestShutdownWorkflow {
    public let context: RuntimeGuestShutdownWorkflowContext
    public let operations: RuntimeGuestShutdownWorkflowOperations

    public init(
        context: RuntimeGuestShutdownWorkflowContext,
        operations: RuntimeGuestShutdownWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func prepareForUpdate(manifest: UpdateBundleManifest) throws {
        try runner().prepareForUpdate(version: manifest.version)
    }

    private func runner() -> RuntimeGuestShutdownRunner {
        RuntimeGuestShutdownRunner(
            executeShutdownPlan: { plan in
                try operations.executeGuestShutdownPlan(plan, context)
            }
        )
    }
}
