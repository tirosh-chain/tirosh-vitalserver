import Application
import Contracts
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

public struct RuntimeRedisBackupResult: Equatable, Sendable {
    public let message: String
    public let archive: String?

    public init(message: String, archive: String?) {
        self.message = message
        self.archive = archive
    }
}

public struct RuntimeRedisBackupWorkflowOperations {
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
    public let context: RuntimeRedisBackupWorkflowContext
    public let operations: RuntimeRedisBackupWorkflowOperations
    private var useCase: RepairRuntimeUseCase {
        RepairRuntimeUseCase()
    }

    public init(
        context: RuntimeRedisBackupWorkflowContext,
        operations: RuntimeRedisBackupWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func createBackup() throws -> RuntimeRedisBackupResult {
        operations.log("redis backup requested")
        try operations.requireCapability()
        try operations.createDirectory(context.guestRunDirectory, true)
        try operations.createDirectory(context.redisBackupsDirectory, true)

        let resultURL = context.guestRunDirectory.appendingPathComponent(context.resultFileName)
        try operations.removePreviousResult(resultURL)

        try operations.writeStatus(.recovering, .redisBackup, "redis backup requested")

        let requestID = operations.requestID()
        let request = RedisBackupRequestDocument(
            requestId: requestID,
            requestedAt: operations.timestamp()
        )
        let requestURL = context.guestRunDirectory.appendingPathComponent(context.requestFileName)
        try operations.writeRequest(request, requestURL)

        if !operations.isVMServiceLoaded() {
            try operations.startVMService()
        }

        let maxAttempts = Int(ceil(context.waitTimeoutSeconds / context.pollIntervalSeconds))
        for attempt in 0..<maxAttempts {
            let decision = useCase.redisBackupResultDecision(
                loadResult: operations.loadResult(resultURL),
                expectedRequestID: requestID,
                shouldReportProgress: attempt % 10 == 0
            )
            switch decision {
            case .ignoreStaleResult(let logMessage):
                operations.log(logMessage)
            case .completed(let message, let archive):
                try operations.writeStatus(.healthy, .redisBackup, message)
                operations.log("redis backup completed")
                return RuntimeRedisBackupResult(message: message, archive: archive)
            case .failed(let message):
                try operations.writeStatus(.degraded, .redisBackup, message)
                throw RuntimeRedisBackupWorkflowError.operationFailed(message)
            case .waiting(let logMessage):
                if let logMessage {
                    operations.log(logMessage)
                }
            case .readFailed(let message):
                try operations.writeStatus(.degraded, .redisBackup, message)
                throw RuntimeRedisBackupWorkflowError.operationFailed(message)
            }
            if attempt < maxAttempts - 1 {
                operations.sleep(context.pollIntervalSeconds)
            }
        }

        try operations.writeStatus(.degraded, .redisBackup, "redis backup timed out")
        throw RuntimeRedisBackupWorkflowError.operationFailed("redis backup timed out")
    }
}
