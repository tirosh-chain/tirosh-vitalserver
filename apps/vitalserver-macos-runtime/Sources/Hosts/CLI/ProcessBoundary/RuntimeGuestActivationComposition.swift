import Application
import Bootstrap
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

    public func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        try RuntimeGuestActivationWorkflow().activateIfNeeded(
            manifest: manifest,
            context: RuntimeGuestActivationWorkflowContext(
                guestRunDirectory: context.guestRunDirectory,
                waitTimeoutSeconds: Constants.Runtime.updateActivationWaitTimeoutSeconds
            ),
            actions: RuntimeGuestActivationWorkflowActions(
                requireCapability: operations.requireCapability,
                createGuestRunDirectory: { directory in
                    try operations.fileStore.createDirectory(at: directory, withIntermediateDirectories: true)
                },
                removeActivationResult: operations.guestGateway.removeUpdateActivationResult,
                writeActivationRequest: operations.guestGateway.writeUpdateActivationRequest,
                loadActivationResult: operations.guestGateway.loadUpdateActivationResultDocument,
                isVMServiceLoaded: operations.isVMServiceLoaded,
                startVMService: operations.startVMService,
                writeProgressStatus: { status, operation, message in
                    writeRuntimeStatusBestEffort(
                        status,
                        operation: operation,
                        message: message,
                        writeStatus: operations.writeStatus,
                        describeError: RuntimeErrorDescription.describe,
                        log: operations.log
                    )
                },
                requestID: operations.requestID,
                timestamp: operations.timestamp,
                sleep: operations.sleep,
                log: operations.log
            )
        )
    }
}
