import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeDatastoreRepairWorkflowContext {
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

public struct RuntimeDatastoreRepairWorkflowOperations {
    public let requireCapability: () throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let removePreviousResult: () throws -> Void
    public let writeRequest: (RuntimeDatastoreRepairRequest) throws -> Void
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let restartVMService: () throws -> Void
    public let loadResult: () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    public let restartProxyService: () throws -> Void
    public let restartWatchdogService: () throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removePreviousResult: @escaping () throws -> Void,
        writeRequest: @escaping (RuntimeDatastoreRepairRequest) throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        restartVMService: @escaping () throws -> Void,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.createDirectory = createDirectory
        self.removePreviousResult = removePreviousResult
        self.writeRequest = writeRequest
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.restartVMService = restartVMService
        self.loadResult = loadResult
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

public struct RuntimeDatastoreRepairWorkflow {
    public let context: RuntimeDatastoreRepairWorkflowContext
    public let operations: RuntimeDatastoreRepairWorkflowOperations

    public init(
        context: RuntimeDatastoreRepairWorkflowContext,
        operations: RuntimeDatastoreRepairWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func repair() throws {
        try runner().run()
    }

    private func runner() -> RuntimeDatastoreRepairRunner {
        RuntimeDatastoreRepairRunner(
            requireCapability: operations.requireCapability,
            prepareGuestRunDirectory: {
                try operations.createDirectory(context.guestRunDirectory, true)
            },
            removePreviousResult: operations.removePreviousResult,
            writeRequest: operations.writeRequest,
            isVMServiceLoaded: operations.isVMServiceLoaded,
            startVMService: operations.startVMService,
            restartVMService: operations.restartVMService,
            waitForResult: { request in
                try waiter().wait(for: request)
            },
            restartProxyService: operations.restartProxyService,
            restartWatchdogService: operations.restartWatchdogService,
            waitForHealth: operations.waitForHealth,
            writeStatus: operations.writeStatus,
            makeRequestID: operations.requestID,
            timestamp: operations.timestamp,
            log: operations.log
        )
    }

    private func waiter() -> RuntimeDatastoreRepairResultWaiter {
        RuntimeDatastoreRepairResultWaiter(
            loadResult: operations.loadResult,
            writeStatus: operations.writeStatus,
            sleep: operations.sleep,
            log: operations.log,
            waitTimeoutSeconds: context.waitTimeoutSeconds
        )
    }
}
