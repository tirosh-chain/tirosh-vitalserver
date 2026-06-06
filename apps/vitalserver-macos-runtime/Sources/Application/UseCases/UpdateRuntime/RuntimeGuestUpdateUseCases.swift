import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestActivationUseCaseContext: Equatable, Sendable {
    public let guestRunDirectory: URL
    public let waitTimeoutSeconds: Double

    public init(guestRunDirectory: URL, waitTimeoutSeconds: Double) {
        self.guestRunDirectory = guestRunDirectory
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }
}

public struct RuntimeGuestActivationUseCaseOperations {
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

public struct ActivateRuntimeGuestUpdateUseCase {
    public init() {}

    public func activateIfNeeded(
        manifest: UpdateBundleManifest,
        context: RuntimeGuestActivationUseCaseContext,
        operations: RuntimeGuestActivationUseCaseOperations
    ) throws {
        let updateUseCase = UpdateRuntimeUseCase()
        switch updateUseCase.guestActivationExecutionPlan(manifest: manifest) {
        case .skip(let logMessage):
            operations.log(logMessage)
        case .activate(let version, let requestLog, let completionLog):
            operations.log(requestLog)
            try operations.requireCapability()
            try operations.createGuestRunDirectory(context.guestRunDirectory)
            try operations.removeActivationResult()
            let request = updateUseCase.guestActivationRequest(
                version: version,
                requestID: operations.requestID(),
                requestedAt: operations.timestamp()
            )
            try operations.writeActivationRequest(request)
            try startVMServiceIfNeeded(updateUseCase: updateUseCase, operations: operations)
            try waitForActivationResult(request, context: context, updateUseCase: updateUseCase, operations: operations)
            operations.log(completionLog)
        }
    }

    private func startVMServiceIfNeeded(
        updateUseCase: UpdateRuntimeUseCase,
        operations: RuntimeGuestActivationUseCaseOperations
    ) throws {
        switch updateUseCase.guestActivationVMStartPlan(isVMServiceLoaded: operations.isVMServiceLoaded()) {
        case .alreadyLoaded:
            return
        case .startService:
            try operations.startVMService()
        }
    }

    private func waitForActivationResult(
        _ request: RuntimeGuestActivationRequest,
        context: RuntimeGuestActivationUseCaseContext,
        updateUseCase: UpdateRuntimeUseCase,
        operations: RuntimeGuestActivationUseCaseOperations
    ) throws {
        operations.log(updateUseCase.guestActivationWaitStartedLogMessage(
            timeoutSeconds: context.waitTimeoutSeconds
        ))
        let waitResult = GuestActivationWaiter.wait(
            expectedRequestId: request.id,
            configuration: updateUseCase.guestActivationWaitConfiguration(
                timeoutSeconds: context.waitTimeoutSeconds
            ),
            loadResult: operations.loadActivationResult,
            onProgress: { message in
                operations.log(message)
                operations.writeProgressStatus(.recovering, .activateGuestUpdate, message)
            },
            sleep: operations.sleep
        )

        try executeWaitResultPlan(updateUseCase.guestActivationWaitResultExecutionPlan(waitResult), operations: operations)
    }

    private func executeWaitResultPlan(
        _ plan: RuntimeGuestWaitResultExecutionPlan,
        operations: RuntimeGuestActivationUseCaseOperations
    ) throws {
        switch plan {
        case .completed(let logMessage):
            operations.log(logMessage)
        case .failed(let logMessage, let failureMessage):
            operations.log(logMessage)
            throw RuntimeGuestUpdateUseCaseError.operationFailed(failureMessage)
        case .failedWithoutLog(let failureMessage):
            throw RuntimeGuestUpdateUseCaseError.operationFailed(failureMessage)
        }
    }
}

public struct RuntimeGuestShutdownUseCaseContext: Equatable, Sendable {
    public let guestRunDirectory: URL
    public let waitTimeoutSeconds: Double

    public init(guestRunDirectory: URL, waitTimeoutSeconds: Double) {
        self.guestRunDirectory = guestRunDirectory
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }
}

public struct RuntimeGuestShutdownUseCaseOperations {
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

public struct PrepareRuntimeGuestShutdownUseCase {
    public init() {}

    public func prepareForUpdate(
        manifest: UpdateBundleManifest,
        context: RuntimeGuestShutdownUseCaseContext,
        operations: RuntimeGuestShutdownUseCaseOperations
    ) throws {
        try prepareForUpdate(version: manifest.version, context: context, operations: operations)
    }

    public func prepareForUpdate(
        version: String,
        context: RuntimeGuestShutdownUseCaseContext,
        operations: RuntimeGuestShutdownUseCaseOperations
    ) throws {
        let updateUseCase = UpdateRuntimeUseCase()
        switch updateUseCase.guestShutdownExecutionPlan(version: version) {
        case .prepare(let version, let requestLog, let readyLog):
            operations.log(requestLog)
            try operations.requireCapability()
            try operations.createGuestRunDirectory(context.guestRunDirectory)
            try operations.removeShutdownResult()
            let request = updateUseCase.guestShutdownRequest(
                version: version,
                requestID: operations.requestID(),
                requestedAt: operations.timestamp()
            )
            try operations.writeShutdownRequest(request)
            try waitForShutdownReady(request, context: context, updateUseCase: updateUseCase, operations: operations)
            operations.log(readyLog)
        }
    }

    private func waitForShutdownReady(
        _ request: RuntimeGuestShutdownRequest,
        context: RuntimeGuestShutdownUseCaseContext,
        updateUseCase: UpdateRuntimeUseCase,
        operations: RuntimeGuestShutdownUseCaseOperations
    ) throws {
        operations.log(updateUseCase.guestShutdownWaitStartedLogMessage(
            timeoutSeconds: context.waitTimeoutSeconds
        ))
        let waitResult = GuestShutdownWaiter.wait(
            expectedRequestId: request.id,
            configuration: updateUseCase.guestShutdownWaitConfiguration(
                timeoutSeconds: context.waitTimeoutSeconds
            ),
            loadResult: operations.loadShutdownResult,
            onProgress: { message in
                operations.log(message)
                operations.writeProgressStatus(.updating, .applyBundle, message)
            },
            sleep: operations.sleep
        )

        try executeWaitResultPlan(updateUseCase.guestShutdownWaitResultExecutionPlan(waitResult), operations: operations)
    }

    private func executeWaitResultPlan(
        _ plan: RuntimeGuestWaitResultExecutionPlan,
        operations: RuntimeGuestShutdownUseCaseOperations
    ) throws {
        switch plan {
        case .completed(let logMessage):
            operations.log(logMessage)
        case .failed(let logMessage, let failureMessage):
            operations.log(logMessage)
            throw RuntimeGuestUpdateUseCaseError.operationFailed(failureMessage)
        case .failedWithoutLog(let failureMessage):
            throw RuntimeGuestUpdateUseCaseError.operationFailed(failureMessage)
        }
    }
}
