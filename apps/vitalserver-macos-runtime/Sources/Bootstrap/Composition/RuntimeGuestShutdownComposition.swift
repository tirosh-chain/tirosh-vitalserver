import Application
import Contracts
import Foundation
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

    public func prepareForUpdate(manifest: UpdateBundleManifest) throws {
        try PrepareRuntimeGuestShutdownUseCase().prepareForUpdate(
            manifest: manifest,
            context: RuntimeGuestShutdownUseCaseContext(
                guestRunDirectory: context.guestRunDirectory,
                waitTimeoutSeconds: Constants.Runtime.updateShutdownWaitTimeoutSeconds
            ),
            operations: RuntimeGuestShutdownUseCaseOperations(
                requireCapability: operations.requireCapability,
                createGuestRunDirectory: { directory in
                    try operations.fileStore.createDirectory(at: directory, withIntermediateDirectories: true)
                },
                removeShutdownResult: operations.guestGateway.removeUpdateShutdownResult,
                writeShutdownRequest: operations.guestGateway.writeUpdateShutdownRequest,
                loadShutdownResult: operations.guestGateway.loadUpdateShutdownResultDocument,
                writeProgressStatus: { status, operation, message in
                    writeRuntimeStatusBestEffort(
                        status,
                        operation: operation,
                        message: message,
                        writeStatus: operations.writeStatus,
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
