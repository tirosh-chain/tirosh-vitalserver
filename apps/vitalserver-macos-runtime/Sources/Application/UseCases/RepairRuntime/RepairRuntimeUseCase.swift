import Contracts
import Domain
import Foundation
import Errors

public struct RepairRuntimeVMDiskInput: Equatable, Sendable {
    public let rootfsBasePath: String
    public let rootfsBaseExists: Bool
    public let rootfsBaseSizeBytes: UInt64
    public let currentVMDiskSizeBytes: UInt64?
    public let defaultDiskGiB: Int
    public let bytesPerGiB: UInt64
    public let freeSpaceMarginBytes: UInt64

    public init(
        rootfsBasePath: String,
        rootfsBaseExists: Bool,
        rootfsBaseSizeBytes: UInt64,
        currentVMDiskSizeBytes: UInt64?,
        defaultDiskGiB: Int,
        bytesPerGiB: UInt64,
        freeSpaceMarginBytes: UInt64
    ) {
        self.rootfsBasePath = rootfsBasePath
        self.rootfsBaseExists = rootfsBaseExists
        self.rootfsBaseSizeBytes = rootfsBaseSizeBytes
        self.currentVMDiskSizeBytes = currentVMDiskSizeBytes
        self.defaultDiskGiB = defaultDiskGiB
        self.bytesPerGiB = bytesPerGiB
        self.freeSpaceMarginBytes = freeSpaceMarginBytes
    }
}

public struct RepairRuntimeVMDiskPlan: Equatable, Sendable {
    public let operation: RuntimeOperation
    public let targetDiskGiB: Int
    public let requiredFreeSpaceBytes: UInt64
    public let shouldArchiveCurrentDisk: Bool
    public let restartPolicy: RuntimeServiceRestartPolicy

    public init(
        operation: RuntimeOperation,
        targetDiskGiB: Int,
        requiredFreeSpaceBytes: UInt64,
        shouldArchiveCurrentDisk: Bool,
        restartPolicy: RuntimeServiceRestartPolicy
    ) {
        self.operation = operation
        self.targetDiskGiB = targetDiskGiB
        self.requiredFreeSpaceBytes = requiredFreeSpaceBytes
        self.shouldArchiveCurrentDisk = shouldArchiveCurrentDisk
        self.restartPolicy = restartPolicy
    }
}

public struct RepairRuntimeVMDiskExecutionPlan: Equatable, Sendable {
    public let temporaryDisk: URL
    public let archiveDirectory: URL
    public let archivedDisk: URL

    public init(
        temporaryDisk: URL,
        archiveDirectory: URL,
        archivedDisk: URL
    ) {
        self.temporaryDisk = temporaryDisk
        self.archiveDirectory = archiveDirectory
        self.archivedDisk = archivedDisk
    }
}

public struct RepairRuntimeVMDiskReplacementObservation: Equatable, Sendable {
    public let path: String
    public let exists: Bool
    public let actualBytes: UInt64?
    public let targetDiskGiB: Int
    public let bytesPerGiB: UInt64

    public init(
        path: String,
        exists: Bool,
        actualBytes: UInt64?,
        targetDiskGiB: Int,
        bytesPerGiB: UInt64
    ) {
        self.path = path
        self.exists = exists
        self.actualBytes = actualBytes
        self.targetDiskGiB = targetDiskGiB
        self.bytesPerGiB = bytesPerGiB
    }
}

public struct RepairRuntimeVMDiskCompletionMessages: Equatable, Sendable {
    public let healthy: String
    public let degraded: String

    public init(healthy: String, degraded: String) {
        self.healthy = healthy
        self.degraded = degraded
    }
}

public struct RepairRuntimeDatastorePlan: Equatable, Sendable {
    public let requestedLogMessage: String
    public let requestedStatusMessage: String
    public let completedLogMessage: String
    public let completedStatusMessage: String
    public let restartPolicy: RuntimeServiceRestartPolicy

    public init(
        requestedLogMessage: String,
        requestedStatusMessage: String,
        completedLogMessage: String,
        completedStatusMessage: String,
        restartPolicy: RuntimeServiceRestartPolicy
    ) {
        self.requestedLogMessage = requestedLogMessage
        self.requestedStatusMessage = requestedStatusMessage
        self.completedLogMessage = completedLogMessage
        self.completedStatusMessage = completedStatusMessage
        self.restartPolicy = restartPolicy
    }
}

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

public struct RepairRuntimeStatusPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let message: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) {
        self.status = status
        self.operation = operation
        self.message = message
    }
}

public struct RepairRuntimeLoggedStatusPlan: Equatable, Sendable {
    public let logMessage: String
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String

    public init(
        logMessage: String,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String
    ) {
        self.logMessage = logMessage
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
    }
}

public struct RepairRuntimeWaitResultPlan: Equatable, Sendable {
    public let logMessage: String?
    public let failureMessage: String?

    public init(logMessage: String?, failureMessage: String?) {
        self.logMessage = logMessage
        self.failureMessage = failureMessage
    }
}

public struct RepairRuntimeFailureStatusPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String
    public let failureMessage: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String,
        failureMessage: String
    ) {
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
        self.failureMessage = failureMessage
    }
}

public struct RepairRuntimeUseCase {
    public init() {}

    public func planVMDiskRepair(for input: RepairRuntimeVMDiskInput) throws -> RepairRuntimeVMDiskPlan {
        guard input.rootfsBaseExists else {
            throw RepairRuntimeUseCaseError.operationFailed("missing file: \(input.rootfsBasePath)")
        }
        guard input.rootfsBaseSizeBytes > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed("rootfs base is empty path=\(input.rootfsBasePath)")
        }
        guard input.defaultDiskGiB > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed("default VM disk size must be positive")
        }
        guard input.bytesPerGiB > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed("bytes per GiB must be positive")
        }

        let requiredFreeSpaceBytes = try requiredFreeSpaceBytes(
            rootfsBaseSizeBytes: input.rootfsBaseSizeBytes,
            freeSpaceMarginBytes: input.freeSpaceMarginBytes
        )
        return RepairRuntimeVMDiskPlan(
            operation: .repairVMDisk,
            targetDiskGiB: targetDiskGiB(
                currentVMDiskSizeBytes: input.currentVMDiskSizeBytes,
                defaultDiskGiB: input.defaultDiskGiB,
                bytesPerGiB: input.bytesPerGiB
            ),
            requiredFreeSpaceBytes: requiredFreeSpaceBytes,
            shouldArchiveCurrentDisk: input.currentVMDiskSizeBytes != nil,
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            )
        )
    }

    public func vmDiskExecutionPlan(
        vmDisk: URL,
        backupsDirectory: URL,
        timestamp: String
    ) -> RepairRuntimeVMDiskExecutionPlan {
        let archiveDirectory = backupsDirectory.appendingPathComponent("vm-disk-repair-\(sanitizedTimestamp(timestamp))")
        return RepairRuntimeVMDiskExecutionPlan(
            temporaryDisk: vmDisk.deletingLastPathComponent()
                .appendingPathComponent(".\(vmDisk.lastPathComponent).repair.tmp"),
            archiveDirectory: archiveDirectory,
            archivedDisk: archiveDirectory.appendingPathComponent(vmDisk.lastPathComponent)
        )
    }

    public func requireReplacementDisk(_ observation: RepairRuntimeVMDiskReplacementObservation) throws {
        guard observation.exists else {
            throw RepairRuntimeUseCaseError.operationFailed("vm disk repair replacement missing path=\(observation.path)")
        }
        guard let actualBytes = observation.actualBytes else {
            throw RepairRuntimeUseCaseError.operationFailed("vm disk repair replacement size missing path=\(observation.path)")
        }
        let expectedBytes = UInt64(observation.targetDiskGiB) * observation.bytesPerGiB
        guard actualBytes >= expectedBytes else {
            throw RepairRuntimeUseCaseError.operationFailed(
                "vm disk repair replacement undersized path=\(observation.path) expectedBytes=\(expectedBytes) actualBytes=\(actualBytes)"
            )
        }
    }

    public func vmDiskCompletionMessages(archivedDiskPath: String?) -> RepairRuntimeVMDiskCompletionMessages {
        guard let archivedDiskPath else {
            return RepairRuntimeVMDiskCompletionMessages(
                healthy: "VM disk repaired.",
                degraded: "VM disk was recreated, but runtime health check failed."
            )
        }
        return RepairRuntimeVMDiskCompletionMessages(
            healthy: "VM disk repaired. Previous disk archive: \(archivedDiskPath)",
            degraded: "VM disk was recreated, but runtime health check failed. Previous disk archive: \(archivedDiskPath)"
        )
    }

    public func datastoreRepairPlan() -> RepairRuntimeDatastorePlan {
        RepairRuntimeDatastorePlan(
            requestedLogMessage: "datastore repair requested",
            requestedStatusMessage: "datastore repair requested",
            completedLogMessage: "datastore repair completed",
            completedStatusMessage: "datastore repair completed",
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            )
        )
    }

    public func datastoreRepairRequest(
        requestID: String,
        requestedAt: String
    ) -> RuntimeDatastoreRepairRequest {
        RuntimeDatastoreRepairRequest(id: requestID, requestedAt: requestedAt)
    }

    public func datastoreRepairWaitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for datastore repair result timeoutSeconds=\(timeoutSeconds)"
    }

    public func datastoreRepairWaitProgressPlan(message: String) -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .recovering,
            operation: .repairDatastore,
            message: message
        )
    }

    public func datastoreRepairWaitResultPlan(
        _ result: DatastoreRepairWaitResult
    ) -> RepairRuntimeWaitResultPlan {
        switch result {
        case .completed(let message):
            return RepairRuntimeWaitResultPlan(
                logMessage: "datastore repair guest result completed message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RepairRuntimeWaitResultPlan(
                logMessage: "datastore repair guest result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return RepairRuntimeWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        }
    }

    public func redisBackupRequestedPlan() -> RepairRuntimeLoggedStatusPlan {
        RepairRuntimeLoggedStatusPlan(
            logMessage: "redis backup requested",
            status: .recovering,
            operation: .redisBackup,
            statusMessage: "redis backup requested"
        )
    }

    public func redisBackupCompletedLogMessage() -> String {
        "redis backup completed"
    }

    public func redisBackupTimedOutPlan() -> RepairRuntimeFailureStatusPlan {
        RepairRuntimeFailureStatusPlan(
            status: .degraded,
            operation: .redisBackup,
            statusMessage: "redis backup timed out",
            failureMessage: "redis backup timed out"
        )
    }

    public func redisBackupResultDecision(
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

    private func targetDiskGiB(
        currentVMDiskSizeBytes: UInt64?,
        defaultDiskGiB: Int,
        bytesPerGiB: UInt64
    ) -> Int {
        guard let currentVMDiskSizeBytes else {
            return defaultDiskGiB
        }
        let currentGiB = Int((currentVMDiskSizeBytes + bytesPerGiB - 1) / bytesPerGiB)
        return max(defaultDiskGiB, currentGiB)
    }

    private func requiredFreeSpaceBytes(
        rootfsBaseSizeBytes: UInt64,
        freeSpaceMarginBytes: UInt64
    ) throws -> UInt64 {
        let multiplied = rootfsBaseSizeBytes.multipliedReportingOverflow(by: 6)
        guard !multiplied.overflow else {
            throw RepairRuntimeUseCaseError.operationFailed("required free space calculation overflowed")
        }
        let added = multiplied.partialValue.addingReportingOverflow(freeSpaceMarginBytes)
        guard !added.overflow else {
            throw RepairRuntimeUseCaseError.operationFailed("required free space calculation overflowed")
        }
        return added.partialValue
    }

    private func sanitizedTimestamp(_ timestamp: String) -> String {
        timestamp
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
