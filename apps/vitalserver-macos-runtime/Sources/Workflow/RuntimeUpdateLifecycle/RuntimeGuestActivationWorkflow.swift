import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestActivationWorkflowContext: Equatable, Sendable {
    public init() {}

    public init(guestRunDirectory _: URL, waitTimeoutSeconds _: Double) {}
}

public struct RuntimeGuestActivationWorkflowActions {
    public let requireCapability: () throws -> Void
    public let activateUpdate: (String, String) throws -> RuntimeGuestControlServiceOperation
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let requestID: () -> String
    public let log: (String) -> Void

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

public struct RuntimeGuestActivationWorkflow {
    private let useCase: RuntimeGuestActivationUseCase

    public init(useCase: RuntimeGuestActivationUseCase = RuntimeGuestActivationUseCase()) {
        self.useCase = useCase
    }

    public func activateIfNeeded(
        manifest: UpdateBundleManifest,
        context: RuntimeGuestActivationWorkflowContext,
        actions: RuntimeGuestActivationWorkflowActions
    ) throws {
        switch useCase.executionPlan(manifest: manifest) {
        case .skip(let logMessage):
            actions.log(logMessage)
        case .activate(let version, let requestLog, let completionLog):
            actions.log(requestLog)
            try actions.requireCapability()
            try startVMServiceIfNeeded(actions: actions)
            let operation = try actions.activateUpdate(actions.requestID(), version)
            actions.log("guest update activation operation completed operationId=\(operation.operationId)")
            actions.log(completionLog)
        }
    }

    private func startVMServiceIfNeeded(
        actions: RuntimeGuestActivationWorkflowActions
    ) throws {
        switch useCase.vmStartPlan(isVMServiceLoaded: actions.isVMServiceLoaded()) {
        case .alreadyLoaded:
            return
        case .startService:
            try actions.startVMService()
        }
    }

}
