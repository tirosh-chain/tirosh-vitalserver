import Application
import Contracts
import Domain
import Foundation
import Workflow
import Errors

public struct RuntimeDatastoreRepairCompositionContext {
    let guestRunDirectory: URL

    public init(guestRunDirectory: URL) {
        self.guestRunDirectory = guestRunDirectory
    }
}

public struct RuntimeDatastoreRepairCompositionOperations {
    let fileStore: RuntimeFileStore
    let guestGateway: RuntimeGuestGateway
    let requireCapability: () throws -> Void
    let isVMServiceLoaded: () -> Bool
    let startVMService: () throws -> Void
    let restartVMService: () throws -> Void
    let restartProxyService: () throws -> Void
    let restartWatchdogService: () throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
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
        restartVMService: @escaping () throws -> Void,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
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
        self.restartVMService = restartVMService
        self.restartProxyService = restartProxyService
        self.restartWatchdogService = restartWatchdogService
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeDatastoreRepairComposition {
    let context: RuntimeDatastoreRepairCompositionContext
    let operations: RuntimeDatastoreRepairCompositionOperations

    public init(
        context: RuntimeDatastoreRepairCompositionContext,
        operations: RuntimeDatastoreRepairCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func workflow() -> RuntimeDatastoreRepairWorkflow {
        RuntimeDatastoreRepairWorkflow(
            context: RuntimeDatastoreRepairWorkflowContext(
                guestRunDirectory: context.guestRunDirectory,
                waitTimeoutSeconds: Constants.Runtime.datastoreRepairWaitTimeoutSeconds
            ),
            operations: RuntimeDatastoreRepairWorkflowOperations(
                requireCapability: operations.requireCapability,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removePreviousResult: {
                    try operations.guestGateway.removeDatastoreRepairResult()
                },
                writeRequest: { request in
                    try operations.guestGateway.writeDatastoreRepairRequest(request)
                },
                isVMServiceLoaded: operations.isVMServiceLoaded,
                startVMService: operations.startVMService,
                restartVMService: operations.restartVMService,
                loadResult: {
                    operations.guestGateway.loadDatastoreRepairResultDocument()
                },
                restartProxyService: operations.restartProxyService,
                restartWatchdogService: operations.restartWatchdogService,
                waitForHealth: operations.waitForHealth,
                writeStatus: operations.writeStatus,
                requestID: operations.requestID,
                timestamp: operations.timestamp,
                sleep: operations.sleep,
                log: operations.log
            )
        )
    }
}
