import Application
import Bootstrap
import Contracts
import Foundation
import Workflow
import Errors

public struct RuntimeGuestActivationCompositionContext {
    public init(guestRunDirectory _: URL) {}
}

public struct RuntimeGuestActivationCompositionOperations {
    let requireCapability: () throws -> Void
    let activateUpdate: (String, String) throws -> RuntimeGuestControlServiceOperation
    let isVMServiceLoaded: () -> Bool
    let startVMService: () throws -> Void
    let requestID: () -> String
    let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        activateUpdate: @escaping (String, String) throws -> RuntimeGuestControlServiceOperation,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        requestID: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.activateUpdate = activateUpdate
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.requestID = requestID
        self.log = log
    }
}

public struct RuntimeGuestActivationComposition {
    let context: RuntimeGuestActivationCompositionContext
    let operations: RuntimeGuestActivationCompositionOperations

    public init(
        context: RuntimeGuestActivationCompositionContext,
        operations: RuntimeGuestActivationCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        try RuntimeGuestActivationWorkflow().activateIfNeeded(
            manifest: manifest,
            context: RuntimeGuestActivationWorkflowContext(),
            actions: RuntimeGuestActivationWorkflowActions(
                requireCapability: operations.requireCapability,
                activateUpdate: operations.activateUpdate,
                isVMServiceLoaded: operations.isVMServiceLoaded,
                startVMService: operations.startVMService,
                requestID: operations.requestID,
                log: operations.log
            )
        )
    }
}
