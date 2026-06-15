import Contracts

public enum RuntimeRedisBackupResultLoadResult: Equatable, Sendable {
    case missing
    case loaded(RedisBackupResultDocument)
    case failed(String)
}

public enum RepairRuntimeRedisBackupResultDecision: Equatable, Sendable {
    case ignoreStaleResult(logMessage: String)
    case completed(message: String, archive: String?)
    case failed(message: String)
    case waiting(logMessage: String?)
    case readFailed(message: String)
}

public struct RuntimeRedisBackupResult: Equatable, Sendable {
    public let message: String
    public let archive: String?

    public init(message: String, archive: String?) {
        self.message = message
        self.archive = archive
    }
}

public struct RuntimeRedisBackupUseCase {
    public init() {}

    public func requestedPlan() -> RepairRuntimeLoggedStatusPlan {
        RepairRuntimeLoggedStatusPlan(
            logMessage: "redis backup requested",
            status: .recovering,
            operation: .redisBackup,
            statusMessage: "redis backup requested"
        )
    }

    public func completedLogMessage() -> String {
        "redis backup completed"
    }

    public func timedOutPlan() -> RepairRuntimeFailureStatusPlan {
        RepairRuntimeFailureStatusPlan(
            status: .degraded,
            operation: .redisBackup,
            statusMessage: "redis backup timed out",
            failureMessage: "redis backup timed out"
        )
    }

    public func resultDecision(
        loadResult: RuntimeRedisBackupResultLoadResult,
        expectedRequestID: String,
        shouldReportProgress: Bool
    ) -> RepairRuntimeRedisBackupResultDecision {
        switch loadResult {
        case .loaded(let result):
            if let resultRequestId = result.requestId, resultRequestId != expectedRequestID {
                return .ignoreStaleResult(logMessage: "stale redis backup result ignored")
            }
            if result.status == .completed {
                return .completed(message: result.message ?? "Redis backup completed.", archive: result.archive)
            }
            if result.status == .failed {
                return .failed(message: result.message ?? "Redis backup failed.")
            }
            return .waiting(logMessage: shouldReportProgress ? result.message ?? "waiting for redis backup" : nil)
        case .missing:
            return .waiting(logMessage: shouldReportProgress ? "waiting for redis backup guest worker" : nil)
        case .failed(let message):
            return .readFailed(message: "failed to read redis backup result: \(message)")
        }
    }
}
