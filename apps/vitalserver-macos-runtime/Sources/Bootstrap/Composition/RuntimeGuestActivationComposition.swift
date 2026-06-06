import Application
import Contracts
import Foundation
import Workflow
import Errors

public struct RuntimeGuestActivationCompositionContext {
    let guestRunDirectory: URL

    public init(guestRunDirectory: URL) {
        self.guestRunDirectory = guestRunDirectory
    }
}

public struct RuntimeGuestActivationCompositionOperations {
    let fileStore: RuntimeFileStore
    let guestGateway: RuntimeGuestGateway
    let requireCapability: () throws -> Void
    let isVMServiceLoaded: () -> Bool
    let startVMService: () throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let requestID: () -> String
    let timestamp: () -> String
    let sleep: () -> Void
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        guestGateway: RuntimeGuestGateway,
        requireCapability: @escaping () throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.guestGateway = guestGateway
        self.requireCapability = requireCapability
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
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

    public func workflow() -> RuntimeGuestActivationWorkflow {
        RuntimeGuestActivationWorkflow(
            context: RuntimeGuestActivationWorkflowContext(
                guestRunDirectory: context.guestRunDirectory,
                waitTimeoutSeconds: Constants.Runtime.updateActivationWaitTimeoutSeconds
            ),
            operations: RuntimeGuestActivationWorkflowOperations(
                requireCapability: operations.requireCapability,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removePreviousResult: {
                    try operations.guestGateway.removeUpdateActivationResult()
                },
                writeRequest: { request in
                    try operations.guestGateway.writeUpdateActivationRequest(request)
                },
                isVMServiceLoaded: operations.isVMServiceLoaded,
                startVMService: operations.startVMService,
                loadResult: {
                    operations.guestGateway.loadUpdateActivationResultDocument()
                },
                writeStatus: operations.writeStatus,
                requestID: operations.requestID,
                timestamp: operations.timestamp,
                sleep: operations.sleep,
                log: operations.log
            )
        )
    }
}
