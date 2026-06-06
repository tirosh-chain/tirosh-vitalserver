import Application
import Contracts
import Foundation
import Workflow
import Errors

public struct RuntimeGuestShutdownCompositionContext {
    let guestRunDirectory: URL

    public init(guestRunDirectory: URL) {
        self.guestRunDirectory = guestRunDirectory
    }
}

public struct RuntimeGuestShutdownCompositionOperations {
    let fileStore: RuntimeFileStore
    let guestGateway: RuntimeGuestGateway
    let requireCapability: () throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let requestID: () -> String
    let timestamp: () -> String
    let sleep: () -> Void
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        guestGateway: RuntimeGuestGateway,
        requireCapability: @escaping () throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.guestGateway = guestGateway
        self.requireCapability = requireCapability
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeGuestShutdownComposition {
    let context: RuntimeGuestShutdownCompositionContext
    let operations: RuntimeGuestShutdownCompositionOperations

    public init(
        context: RuntimeGuestShutdownCompositionContext,
        operations: RuntimeGuestShutdownCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func workflow() -> RuntimeGuestShutdownWorkflow {
        RuntimeGuestShutdownWorkflow(
            context: RuntimeGuestShutdownWorkflowContext(
                guestRunDirectory: context.guestRunDirectory,
                waitTimeoutSeconds: Constants.Runtime.updateShutdownWaitTimeoutSeconds
            ),
            operations: RuntimeGuestShutdownWorkflowOperations(
                requireCapability: operations.requireCapability,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removePreviousResult: {
                    try operations.guestGateway.removeUpdateShutdownResult()
                },
                writeRequest: { request in
                    try operations.guestGateway.writeUpdateShutdownRequest(request)
                },
                loadResult: {
                    operations.guestGateway.loadUpdateShutdownResultDocument()
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
