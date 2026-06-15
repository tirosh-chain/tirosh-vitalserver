import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestActivationWorkflowContext: Equatable, Sendable {
    public let guestRunDirectory: URL
    public let waitTimeoutSeconds: Double

    public init(guestRunDirectory: URL, waitTimeoutSeconds: Double) {
        self.guestRunDirectory = guestRunDirectory
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }
}

public struct RuntimeGuestActivationWorkflowActions {
    public let requireCapability: () throws -> Void
    public let createGuestRunDirectory: (URL) throws -> Void
    public let removeActivationResult: () throws -> Void
    public let writeActivationRequest: (RuntimeGuestActivationRequest) throws -> Void
    public let loadActivationResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let writeProgressStatus: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createGuestRunDirectory: @escaping (URL) throws -> Void,
        removeActivationResult: @escaping () throws -> Void,
        writeActivationRequest: @escaping (RuntimeGuestActivationRequest) throws -> Void,
        loadActivationResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        writeProgressStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.createGuestRunDirectory = createGuestRunDirectory
        self.removeActivationResult = removeActivationResult
        self.writeActivationRequest = writeActivationRequest
        self.loadActivationResult = loadActivationResult
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.writeProgressStatus = writeProgressStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeGuestActivationWorkflow {
    private let useCase: RuntimeGuestActivationUseCase

    public init(useCase: RuntimeGuestActivationUseCase = RuntimeGuestActivationUseCase()) {
        self.useCase = useCase
    }

    public func activateIfNeeded(
        manifest: UpdateBundleManifest,
        context: RuntimeGuestActivationWorkflowContext,
        actions: RuntimeGuestActivationWorkflowActions
    ) throws {
        switch useCase.executionPlan(manifest: manifest) {
        case .skip(let logMessage):
            actions.log(logMessage)
        case .activate(let version, let requestLog, let completionLog):
            actions.log(requestLog)
            try actions.requireCapability()
            try actions.createGuestRunDirectory(context.guestRunDirectory)
            try actions.removeActivationResult()
            let request = useCase.request(
                version: version,
                requestID: actions.requestID(),
                requestedAt: actions.timestamp()
            )
            try actions.writeActivationRequest(request)
            try startVMServiceIfNeeded(actions: actions)
            try waitForActivationResult(request, context: context, actions: actions)
            actions.log(completionLog)
        }
    }

    private func startVMServiceIfNeeded(
        actions: RuntimeGuestActivationWorkflowActions
    ) throws {
        switch useCase.vmStartPlan(isVMServiceLoaded: actions.isVMServiceLoaded()) {
        case .alreadyLoaded:
            return
        case .startService:
            try actions.startVMService()
        }
    }

    private func waitForActivationResult(
        _ request: RuntimeGuestActivationRequest,
        context: RuntimeGuestActivationWorkflowContext,
        actions: RuntimeGuestActivationWorkflowActions
    ) throws {
        actions.log(useCase.waitStartedLogMessage(
            timeoutSeconds: context.waitTimeoutSeconds
        ))
        let configuration = try useCase.waitConfiguration(
            timeoutSeconds: context.waitTimeoutSeconds
        )
        for attempt in 0..<configuration.maxAttempts {
            let outcome = GuestActivationWaiter.evaluateAttempt(
                expectedRequestId: request.id,
                configuration: configuration,
                attempt: attempt,
                loadResult: actions.loadActivationResult()
            )
            switch outcome {
            case .completed(let message):
                try executeWaitResultPlan(
                    useCase.waitResultExecutionPlan(.completed(message: message)),
                    actions: actions
                )
                return
            case .failed(let message):
                try executeWaitResultPlan(
                    useCase.waitResultExecutionPlan(.failed(message: message)),
                    actions: actions
                )
                return
            case .waiting(let message, let shouldPublishProgress):
                if shouldPublishProgress {
                    actions.log(message)
                    actions.writeProgressStatus(.recovering, .activateGuestUpdate, message)
                }
                if attempt < configuration.maxAttempts - 1 {
                    actions.sleep()
                }
            }
        }

        try executeWaitResultPlan(
            useCase.waitResultExecutionPlan(.timedOut),
            actions: actions
        )
    }

    private func executeWaitResultPlan(
        _ plan: RuntimeGuestWaitResultExecutionPlan,
        actions: RuntimeGuestActivationWorkflowActions
    ) throws {
        switch plan {
        case .completed(let logMessage):
            actions.log(logMessage)
        case .failed(let logMessage, let failureMessage):
            actions.log(logMessage)
            throw RuntimeGuestUpdateUseCaseError.operationFailed(failureMessage)
        case .failedWithoutLog(let failureMessage):
            throw RuntimeGuestUpdateUseCaseError.operationFailed(failureMessage)
        }
    }
}
