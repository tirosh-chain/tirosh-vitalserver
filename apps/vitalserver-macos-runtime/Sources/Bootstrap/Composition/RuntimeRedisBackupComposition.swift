import Application
import Contracts
import Foundation
import OutboundAdapters
import Workflow
import Errors

public struct RuntimeRedisBackupCompositionContext {
    let guestRunDirectory: URL
    let redisBackupsDirectory: URL

    public init(
        guestRunDirectory: URL,
        redisBackupsDirectory: URL
    ) {
        self.guestRunDirectory = guestRunDirectory
        self.redisBackupsDirectory = redisBackupsDirectory
    }
}

public struct RuntimeRedisBackupCompositionOperations {
    let fileStore: RuntimeFileStore
    let requireCapability: () throws -> Void
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let requestID: () -> String
    let timestamp: () -> String
    let isVMServiceLoaded: () -> Bool
    let startVMService: () throws -> Void
    let sleep: (TimeInterval) -> Void
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        requireCapability: @escaping () throws -> Void,
        writeRuntimeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.requireCapability = requireCapability
        self.writeRuntimeStatus = writeRuntimeStatus
        self.requestID = requestID
        self.timestamp = timestamp
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeRedisBackupComposition {
    let context: RuntimeRedisBackupCompositionContext
    let operations: RuntimeRedisBackupCompositionOperations

    public init(
        context: RuntimeRedisBackupCompositionContext,
        operations: RuntimeRedisBackupCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func workflow() -> RuntimeRedisBackupWorkflow {
        RuntimeRedisBackupWorkflow(
            context: RuntimeRedisBackupWorkflowContext(
                guestRunDirectory: context.guestRunDirectory,
                redisBackupsDirectory: context.redisBackupsDirectory,
                requestFileName: Constants.Runtime.redisBackupRequestFile,
                resultFileName: Constants.Runtime.redisBackupResultFile,
                waitTimeoutSeconds: Constants.Runtime.redisBackupWaitTimeoutSeconds,
                pollIntervalSeconds: 3
            ),
            operations: RuntimeRedisBackupWorkflowOperations(
                requireCapability: operations.requireCapability,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removePreviousResult: { url in
                    if operations.fileStore.fileExists(url) {
                        try operations.fileStore.removeItem(at: url)
                    }
                },
                writeStatus: operations.writeRuntimeStatus,
                requestID: operations.requestID,
                timestamp: operations.timestamp,
                writeRequest: { request, url in
                    try operations.fileStore.writeData(
                        try Self.prettyJSONEncoder().encode(request),
                        to: url,
                        options: .atomic
                    )
                },
                isVMServiceLoaded: operations.isVMServiceLoaded,
                startVMService: operations.startVMService,
                loadResult: { url in
                    RedisBackupResultReader.load(from: url, fileStore: operations.fileStore)
                },
                executeResultDecision: executeResultDecision,
                sleep: operations.sleep,
                log: operations.log
            )
        )
    }

    private func executeResultDecision(
        _ decision: RepairRuntimeRedisBackupResultDecision
    ) throws -> RuntimeRedisBackupResult? {
        switch decision {
        case .ignoreStaleResult(let logMessage):
            operations.log(logMessage)
            return nil
        case .completed(let message, let archive):
            try operations.writeRuntimeStatus(.healthy, .redisBackup, message)
            operations.log(RepairRuntimeUseCase().redisBackupCompletedLogMessage())
            return RuntimeRedisBackupResult(message: message, archive: archive)
        case .failed(let message):
            try operations.writeRuntimeStatus(.degraded, .redisBackup, message)
            throw RuntimeRedisBackupWorkflowError.operationFailed(message)
        case .waiting(let logMessage):
            if let logMessage {
                operations.log(logMessage)
            }
            return nil
        case .readFailed(let message):
            try operations.writeRuntimeStatus(.degraded, .redisBackup, message)
            throw RuntimeRedisBackupWorkflowError.operationFailed(message)
        }
    }

    private static func prettyJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
