import Application
import Contracts
import Domain
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
                executeGuestShutdownPlan: { plan, workflowContext in
                    try Self.executeGuestShutdownPlan(
                        plan,
                        workflowContext: workflowContext,
                        operations: operations
                    )
                }
            )
        )
    }

    private static func executeGuestShutdownPlan(
        _ plan: RuntimeGuestShutdownExecutionPlan,
        workflowContext: RuntimeGuestShutdownWorkflowContext,
        operations: RuntimeGuestShutdownCompositionOperations
    ) throws {
        let useCase = UpdateRuntimeUseCase()
        switch plan {
        case .prepare(let version, let requestLog, let readyLog):
            operations.log(requestLog)
            try operations.requireCapability()
            try operations.fileStore.createDirectory(
                at: workflowContext.guestRunDirectory,
                withIntermediateDirectories: true
            )
            try operations.guestGateway.removeUpdateShutdownResult()
            let request = useCase.guestShutdownRequest(
                version: version,
                requestID: operations.requestID(),
                requestedAt: operations.timestamp()
            )
            try operations.guestGateway.writeUpdateShutdownRequest(request)
            try waitForShutdownReady(
                request,
                waitTimeoutSeconds: workflowContext.waitTimeoutSeconds,
                operations: operations,
                useCase: useCase
            )
            operations.log(readyLog)
        }
    }

    private static func waitForShutdownReady(
        _ request: RuntimeGuestShutdownRequest,
        waitTimeoutSeconds: Double,
        operations: RuntimeGuestShutdownCompositionOperations,
        useCase: UpdateRuntimeUseCase
    ) throws {
        operations.log(useCase.guestShutdownWaitStartedLogMessage(timeoutSeconds: waitTimeoutSeconds))
        let waitResult = GuestShutdownWaiter.wait(
            expectedRequestId: request.id,
            configuration: useCase.guestShutdownWaitConfiguration(timeoutSeconds: waitTimeoutSeconds),
            loadResult: {
                operations.guestGateway.loadUpdateShutdownResultDocument()
            },
            onProgress: { message in
                operations.log(message)
                writeRuntimeStatusBestEffort(
                    .updating,
                    operation: .applyBundle,
                    message: message,
                    writeStatus: operations.writeStatus,
                    log: operations.log
                )
            },
            sleep: operations.sleep
        )

        try executeGuestShutdownWaitResultPlan(
            useCase.guestShutdownWaitResultExecutionPlan(waitResult),
            operations: operations
        )
    }

    private static func executeGuestShutdownWaitResultPlan(
        _ plan: RuntimeGuestWaitResultExecutionPlan,
        operations: RuntimeGuestShutdownCompositionOperations
    ) throws {
        switch plan {
        case .completed(let logMessage):
            operations.log(logMessage)
        case .failed(let logMessage, let failureMessage):
            operations.log(logMessage)
            throw RuntimeGuestShutdownWorkflowError.operationFailed(failureMessage)
        case .failedWithoutLog(let failureMessage):
            throw RuntimeGuestShutdownWorkflowError.operationFailed(failureMessage)
        }
    }
}
