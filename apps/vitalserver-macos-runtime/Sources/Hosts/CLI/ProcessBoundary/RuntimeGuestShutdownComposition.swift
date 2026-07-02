import Application
import Bootstrap
import Contracts
import Foundation
import Workflow
import Errors

public struct RuntimeGuestShutdownCompositionContext {
    public init(guestRunDirectory _: URL) {}
}

public struct RuntimeGuestShutdownCompositionOperations {
    let requireCapability: () throws -> Void
    let prepareUpdateShutdown: (String, String) throws -> RuntimeGuestControlServiceOperation
    let loadOperation: (String) throws -> RuntimeGuestControlServiceOperation
    let requestGuestPoweroff: () throws -> RuntimeGuestControlServiceOperation
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let requestID: () -> String
    let sleep: () -> Void
    let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        prepareUpdateShutdown: @escaping (String, String) throws -> RuntimeGuestControlServiceOperation,
        loadOperation: @escaping (String) throws -> RuntimeGuestControlServiceOperation,
        requestGuestPoweroff: @escaping () throws -> RuntimeGuestControlServiceOperation,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.prepareUpdateShutdown = prepareUpdateShutdown
        self.loadOperation = loadOperation
        self.requestGuestPoweroff = requestGuestPoweroff
        self.writeStatus = writeStatus
        self.requestID = requestID
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
        try prepare(version: manifest.version)
    }

    public func prepare(
        version: String,
        progressStatus: RuntimeStatusLevel = .updating,
        progressOperation: RuntimeOperation = .applyBundle
    ) throws {
        try RuntimeGuestShutdownWorkflow().prepareForUpdate(
            version: version,
            context: RuntimeGuestShutdownWorkflowContext(
                guestRunDirectory: URL(fileURLWithPath: "/"),
                waitTimeoutSeconds: Constants.Runtime.updateShutdownWaitTimeoutSeconds,
                progressStatus: progressStatus,
                progressOperation: progressOperation
            ),
            actions: RuntimeGuestShutdownWorkflowActions(
                requireCapability: operations.requireCapability,
                prepareUpdateShutdown: operations.prepareUpdateShutdown,
                loadOperation: operations.loadOperation,
                requestGuestPoweroff: operations.requestGuestPoweroff,
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
                sleep: operations.sleep,
                log: operations.log
            )
        )
    }
}
