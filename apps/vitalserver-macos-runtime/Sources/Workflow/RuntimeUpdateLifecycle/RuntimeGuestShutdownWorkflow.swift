import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestShutdownWorkflowContext: Equatable, Sendable {
    public let guestRunDirectory: URL
    public let waitTimeoutSeconds: Double

    public init(guestRunDirectory: URL, waitTimeoutSeconds: Double) {
        self.guestRunDirectory = guestRunDirectory
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }
}

public struct RuntimeGuestShutdownWorkflowActions {
    public let requireCapability: () throws -> Void
    public let createGuestRunDirectory: (URL) throws -> Void
    public let removeShutdownResult: () throws -> Void
    public let writeShutdownRequest: (RuntimeGuestShutdownRequest) throws -> Void
    public let loadShutdownResult: () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    public let writeProgressStatus: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createGuestRunDirectory: @escaping (URL) throws -> Void,
        removeShutdownResult: @escaping () throws -> Void,
        writeShutdownRequest: @escaping (RuntimeGuestShutdownRequest) throws -> Void,
        loadShutdownResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>,
        writeProgressStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.createGuestRunDirectory = createGuestRunDirectory
        self.removeShutdownResult = removeShutdownResult
        self.writeShutdownRequest = writeShutdownRequest
        self.loadShutdownResult = loadShutdownResult
        self.writeProgressStatus = writeProgressStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeGuestShutdownWorkflow {
    public init() {}

    public func prepareForUpdate(
        manifest: UpdateBundleManifest,
        context: RuntimeGuestShutdownWorkflowContext,
        actions: RuntimeGuestShutdownWorkflowActions
    ) throws {
        try prepareForUpdate(version: manifest.version, context: context, actions: actions)
    }

    public func prepareForUpdate(
        version: String,
        context: RuntimeGuestShutdownWorkflowContext,
        actions: RuntimeGuestShutdownWorkflowActions
    ) throws {
        let updateUseCase = UpdateRuntimeUseCase()
        switch updateUseCase.guestShutdownExecutionPlan(version: version) {
        case .prepare(let version, let requestLog, let readyLog):
            actions.log(requestLog)
            try actions.requireCapability()
            try actions.createGuestRunDirectory(context.guestRunDirectory)
            try actions.removeShutdownResult()
            let request = updateUseCase.guestShutdownRequest(
                version: version,
                requestID: actions.requestID(),
                requestedAt: actions.timestamp()
            )
            try actions.writeShutdownRequest(request)
            try waitForShutdownReady(request, context: context, updateUseCase: updateUseCase, actions: actions)
            actions.log(readyLog)
        }
    }

    private func waitForShutdownReady(
        _ request: RuntimeGuestShutdownRequest,
        context: RuntimeGuestShutdownWorkflowContext,
        updateUseCase: UpdateRuntimeUseCase,
        actions: RuntimeGuestShutdownWorkflowActions
    ) throws {
        actions.log(updateUseCase.guestShutdownWaitStartedLogMessage(
            timeoutSeconds: context.waitTimeoutSeconds
        ))
        let waitResult = GuestShutdownWaiter.wait(
            expectedRequestId: request.id,
            configuration: updateUseCase.guestShutdownWaitConfiguration(
                timeoutSeconds: context.waitTimeoutSeconds
            ),
            loadResult: actions.loadShutdownResult,
            onProgress: { message in
                actions.log(message)
                actions.writeProgressStatus(.updating, .applyBundle, message)
            },
            sleep: actions.sleep
        )

        try executeWaitResultPlan(updateUseCase.guestShutdownWaitResultExecutionPlan(waitResult), actions: actions)
    }

    private func executeWaitResultPlan(
        _ plan: RuntimeGuestWaitResultExecutionPlan,
        actions: RuntimeGuestShutdownWorkflowActions
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
