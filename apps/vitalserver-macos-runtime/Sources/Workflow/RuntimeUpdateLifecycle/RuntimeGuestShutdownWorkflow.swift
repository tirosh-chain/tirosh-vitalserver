import Contracts
import Domain
import Foundation

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
    public let requireCapability: () throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let removePreviousResult: () throws -> Void
    public let writeRequest: (RuntimeGuestShutdownRequest) throws -> Void
    public let loadResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removePreviousResult: @escaping () throws -> Void,
        writeRequest: @escaping (RuntimeGuestShutdownRequest) throws -> Void,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>,
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
        self.loadResult = loadResult
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
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
            requireCapability: operations.requireCapability,
            createRunDirectory: {
                try operations.createDirectory(context.guestRunDirectory, true)
            },
            removePreviousResult: operations.removePreviousResult,
            requestID: operations.requestID,
            timestamp: operations.timestamp,
            writeRequest: operations.writeRequest,
            loadResult: operations.loadResult,
            reportProgress: { message in
                writeRuntimeStatusBestEffort(
                    .updating,
                    operation: .applyBundle,
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
