import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRedisBackupWorkflowContext: Equatable, Sendable {
    public let guestRunDirectory: URL
    public let redisBackupsDirectory: URL
    public let requestFileName: String
    public let resultFileName: String
    public let waitTimeoutSeconds: TimeInterval
    public let pollIntervalSeconds: TimeInterval

    public init(
        guestRunDirectory: URL,
        redisBackupsDirectory: URL,
        requestFileName: String,
        resultFileName: String,
        waitTimeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval
    ) {
        self.guestRunDirectory = guestRunDirectory
        self.redisBackupsDirectory = redisBackupsDirectory
        self.requestFileName = requestFileName
        self.resultFileName = resultFileName
        self.waitTimeoutSeconds = waitTimeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

public struct RuntimeRedisBackupWorkflowActions {
    public let requireCapability: () throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let removePreviousResult: (URL) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let writeRequest: (RedisBackupRequestDocument, URL) throws -> Void
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let loadResult: (URL) -> RuntimeRedisBackupResultLoadResult
    public let sleep: (TimeInterval) -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removePreviousResult: @escaping (URL) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        writeRequest: @escaping (RedisBackupRequestDocument, URL) throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        loadResult: @escaping (URL) -> RuntimeRedisBackupResultLoadResult,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.createDirectory = createDirectory
        self.removePreviousResult = removePreviousResult
        self.writeStatus = writeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.writeRequest = writeRequest
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.loadResult = loadResult
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeRedisBackupWorkflow {
    private let useCase: RepairRuntimeUseCase

    public init(useCase: RepairRuntimeUseCase = RepairRuntimeUseCase()) {
        self.useCase = useCase
    }

    public func createBackup(
        context: RuntimeRedisBackupWorkflowContext,
        actions: RuntimeRedisBackupWorkflowActions
    ) throws -> RuntimeRedisBackupResult {
        let requestedPlan = useCase.redisBackupRequestedPlan()
        actions.log(requestedPlan.logMessage)
        try actions.requireCapability()
        try actions.createDirectory(context.guestRunDirectory, true)
        try actions.createDirectory(context.redisBackupsDirectory, true)

        let resultURL = context.guestRunDirectory.appendingPathComponent(context.resultFileName)
        try actions.removePreviousResult(resultURL)

        try actions.writeStatus(
            requestedPlan.status,
            requestedPlan.operation,
            requestedPlan.statusMessage
        )

        let requestID = actions.requestID()
        let request = RedisBackupRequestDocument(
            requestId: requestID,
            requestedAt: actions.timestamp()
        )
        let requestURL = context.guestRunDirectory.appendingPathComponent(context.requestFileName)
        try actions.writeRequest(request, requestURL)

        if !actions.isVMServiceLoaded() {
            try actions.startVMService()
        }

        let maxAttempts = Int(ceil(context.waitTimeoutSeconds / context.pollIntervalSeconds))
        for attempt in 0..<maxAttempts {
            let decision = useCase.redisBackupResultDecision(
                loadResult: actions.loadResult(resultURL),
                expectedRequestID: requestID,
                shouldReportProgress: attempt % 10 == 0
            )
            if let result = try executeRedisBackupResultDecision(decision, actions: actions) {
                return result
            }
            if attempt < maxAttempts - 1 {
                actions.sleep(context.pollIntervalSeconds)
            }
        }

        let timedOutPlan = useCase.redisBackupTimedOutPlan()
        try actions.writeStatus(
            timedOutPlan.status,
            timedOutPlan.operation,
            timedOutPlan.statusMessage
        )
        throw RuntimeRedisBackupUseCaseError.operationFailed(timedOutPlan.failureMessage)
    }

    private func executeRedisBackupResultDecision(
        _ decision: RepairRuntimeRedisBackupResultDecision,
        actions: RuntimeRedisBackupWorkflowActions
    ) throws -> RuntimeRedisBackupResult? {
        switch decision {
        case .ignoreStaleResult(let logMessage):
            actions.log(logMessage)
            return nil
        case .completed(let message, let archive):
            try actions.writeStatus(.healthy, .redisBackup, message)
            actions.log(useCase.redisBackupCompletedLogMessage())
            return RuntimeRedisBackupResult(message: message, archive: archive)
        case .failed(let message):
            try actions.writeStatus(.degraded, .redisBackup, message)
            throw RuntimeRedisBackupUseCaseError.operationFailed(message)
        case .waiting(let logMessage):
            if let logMessage {
                actions.log(logMessage)
            }
            return nil
        case .readFailed(let message):
            try actions.writeStatus(.degraded, .redisBackup, message)
            throw RuntimeRedisBackupUseCaseError.operationFailed(message)
        }
    }
}
