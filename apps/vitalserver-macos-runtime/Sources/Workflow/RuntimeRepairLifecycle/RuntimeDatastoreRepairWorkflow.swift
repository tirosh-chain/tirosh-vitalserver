import Foundation
import Application
import Contracts
import Domain
import Errors

public struct RunDatastoreRepairContext: Equatable, Sendable {
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

public struct RunDatastoreRepairOperations {
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
    public let describeError: (Error) -> String
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
        describeError: @escaping (Error) -> String,
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
        self.describeError = describeError
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeDatastoreRepairWorkflow {
    public init() {}

    public func repair(
        context: RunDatastoreRepairContext,
        operations: RunDatastoreRepairOperations
    ) throws {
        let useCase = RuntimeDatastoreRepairUseCase()
        let plan = useCase.plan()
        operations.log(plan.requestedLogMessage)
        try operations.requireCapability()
        try operations.createDirectory(context.guestRunDirectory, true)
        try operations.removePreviousResult()
        try operations.writeStatus(.recovering, .repairDatastore, plan.requestedStatusMessage)

        let request = useCase.request(
            requestID: operations.requestID(),
            requestedAt: operations.timestamp()
        )
        try operations.writeRequest(request)

        if operations.isVMServiceLoaded() {
            try operations.restartVMService()
        } else {
            try operations.startVMService()
        }

        try waitForDatastoreRepairResult(
            useCase: useCase,
            request: request,
            context: RuntimeDatastoreRepairWaitContext(
                waitTimeoutSeconds: context.waitTimeoutSeconds,
                pollIntervalSeconds: 3.0,
                progressEveryAttempts: 5
            ),
            operations: operations
        )
        try operations.restartProxyService()
        try operations.restartWatchdogService()
        try operations.waitForHealth(plan.restartPolicy)
        try operations.writeStatus(.healthy, .repairDatastore, plan.completedStatusMessage)
        operations.log(plan.completedLogMessage)
    }

    private func waitForDatastoreRepairResult(
        useCase: RuntimeDatastoreRepairUseCase,
        request: RuntimeDatastoreRepairRequest,
        context: RuntimeDatastoreRepairWaitContext,
        operations: RunDatastoreRepairOperations
    ) throws {
        operations.log(useCase.waitStartedLogMessage(timeoutSeconds: context.waitTimeoutSeconds))
        let configuration = try datastoreRepairWaitConfiguration(context)
        var waitResult: DatastoreRepairWaitResult?
        for attempt in 0..<configuration.maxAttempts {
            let outcome = DatastoreRepairWaiter.evaluateAttempt(
                expectedRequestId: request.id,
                configuration: configuration,
                attempt: attempt,
                loadResult: operations.loadResult()
            )
            switch outcome {
            case .completed(let message):
                waitResult = .completed(message: message)
                break
            case .failed(let message):
                waitResult = .failed(message: message)
                break
            case .waiting(let message, let shouldPublishProgress):
                if shouldPublishProgress {
                    let progressPlan = useCase.waitProgressPlan(message: message)
                    operations.log(message)
                    writeRuntimeStatusBestEffort(
                        progressPlan.status,
                        operation: progressPlan.operation,
                        message: progressPlan.message,
                        writeStatus: operations.writeStatus,
                        describeError: operations.describeError,
                        log: operations.log
                    )
                }
                if attempt < configuration.maxAttempts - 1 {
                    operations.sleep()
                }
            }
            if waitResult != nil {
                break
            }
        }

        let resultPlan = useCase.waitResultPlan(waitResult ?? .timedOut)
        if let logMessage = resultPlan.logMessage {
            operations.log(logMessage)
        }
        if let failureMessage = resultPlan.failureMessage {
            throw RepairRuntimeUseCaseError.operationFailed(failureMessage)
        }
    }

    private func datastoreRepairWaitConfiguration(
        _ context: RuntimeDatastoreRepairWaitContext
    ) throws -> DatastoreRepairWaitConfiguration {
        guard context.waitTimeoutSeconds.isFinite, context.waitTimeoutSeconds > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed(
                "invalid datastore repair wait configuration: waitTimeoutSeconds must be positive"
            )
        }
        guard context.pollIntervalSeconds.isFinite, context.pollIntervalSeconds > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed(
                "invalid datastore repair wait configuration: pollIntervalSeconds must be positive"
            )
        }
        guard context.progressEveryAttempts > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed(
                "invalid datastore repair wait configuration: progressEveryAttempts must be positive"
            )
        }
        return DatastoreRepairWaitConfiguration(
            maxAttempts: Int(ceil(context.waitTimeoutSeconds / context.pollIntervalSeconds)),
            progressEveryAttempts: context.progressEveryAttempts
        )
    }
}

private struct RuntimeDatastoreRepairWaitContext: Equatable, Sendable {
    let waitTimeoutSeconds: Double
    let pollIntervalSeconds: Double
    let progressEveryAttempts: Int
}
