import Application
import Contracts
import Domain
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
                executeGuestActivationPlan: { plan, workflowContext in
                    try Self.executeGuestActivationPlan(
                        plan,
                        workflowContext: workflowContext,
                        operations: operations
                    )
                }
            )
        )
    }

    private static func executeGuestActivationPlan(
        _ plan: RuntimeGuestActivationExecutionPlan,
        workflowContext: RuntimeGuestActivationWorkflowContext,
        operations: RuntimeGuestActivationCompositionOperations
    ) throws {
        switch plan {
        case .skip(let logMessage):
            operations.log(logMessage)
        case .activate(let version, let requestLog, let completionLog):
            operations.log(requestLog)
            try operations.requireCapability()
            try operations.fileStore.createDirectory(
                at: workflowContext.guestRunDirectory,
                withIntermediateDirectories: true
            )
            try operations.guestGateway.removeUpdateActivationResult()
            let request = UpdateRuntimeUseCase().guestActivationRequest(
                version: version,
                requestID: operations.requestID(),
                requestedAt: operations.timestamp()
            )
            try operations.guestGateway.writeUpdateActivationRequest(request)
            try startVMServiceIfNeeded(operations: operations)
            try waitForActivationResult(
                request,
                waitTimeoutSeconds: workflowContext.waitTimeoutSeconds,
                operations: operations
            )
            operations.log(completionLog)
        }
    }

    private static func startVMServiceIfNeeded(
        operations: RuntimeGuestActivationCompositionOperations
    ) throws {
        switch UpdateRuntimeUseCase().guestActivationVMStartPlan(isVMServiceLoaded: operations.isVMServiceLoaded()) {
        case .alreadyLoaded:
            return
        case .startService:
            try operations.startVMService()
        }
    }

    private static func waitForActivationResult(
        _ request: RuntimeGuestActivationRequest,
        waitTimeoutSeconds: Double,
        operations: RuntimeGuestActivationCompositionOperations
    ) throws {
        let useCase = UpdateRuntimeUseCase()
        operations.log(useCase.guestActivationWaitStartedLogMessage(timeoutSeconds: waitTimeoutSeconds))
        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: request.id,
            configuration: useCase.guestActivationWaitConfiguration(timeoutSeconds: waitTimeoutSeconds),
            loadResult: {
                operations.guestGateway.loadUpdateActivationResultDocument()
            },
            onProgress: { message in
                operations.log(message)
                writeRuntimeStatusBestEffort(
                    .recovering,
                    operation: .activateGuestUpdate,
                    message: message,
                    writeStatus: operations.writeStatus,
                    log: operations.log
                )
            },
            sleep: operations.sleep
        )

        try executeGuestActivationWaitResultPlan(
            useCase.guestActivationWaitResultExecutionPlan(waitResult),
            operations: operations
        )
    }

    private static func executeGuestActivationWaitResultPlan(
        _ plan: RuntimeGuestWaitResultExecutionPlan,
        operations: RuntimeGuestActivationCompositionOperations
    ) throws {
        switch plan {
        case .completed(let logMessage):
            operations.log(logMessage)
        case .failed(let logMessage, let failureMessage):
            operations.log(logMessage)
            throw RuntimeGuestActivationWorkflowError.operationFailed(failureMessage)
        case .failedWithoutLog(let failureMessage):
            throw RuntimeGuestActivationWorkflowError.operationFailed(failureMessage)
        }
    }
}
