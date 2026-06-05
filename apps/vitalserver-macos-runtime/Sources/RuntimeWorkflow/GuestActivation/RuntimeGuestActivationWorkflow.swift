import Contracts
import Core
import Foundation

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
    public let requireCapability: () throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let removePreviousResult: () throws -> Void
    public let writeRequest: (RuntimeGuestActivationRequest) throws -> Void
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removePreviousResult: @escaping () throws -> Void,
        writeRequest: @escaping (RuntimeGuestActivationRequest) throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>,
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
        self.loadResult = loadResult
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
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
            requireCapability: operations.requireCapability,
            createRunDirectory: {
                try operations.createDirectory(context.guestRunDirectory, true)
            },
            removePreviousResult: operations.removePreviousResult,
            requestID: operations.requestID,
            timestamp: operations.timestamp,
            writeRequest: operations.writeRequest,
            isVMServiceLoaded: operations.isVMServiceLoaded,
            startVMService: operations.startVMService,
            loadResult: operations.loadResult,
            reportProgress: { message in
                writeRuntimeStatusBestEffort(
                    .recovering,
                    operation: .activateGuestUpdate,
                    message: message,
                    writeStatus: operations.writeStatus,
                    log: operations.log
                )
            },
            sleep: operations.sleep,
            log: operations.log,
            waitTimeoutSeconds: context.waitTimeoutSeconds
        )
    }
}
