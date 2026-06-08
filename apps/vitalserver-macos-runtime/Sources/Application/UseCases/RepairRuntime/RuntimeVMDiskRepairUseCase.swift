import Contracts
import Domain
import Foundation
import Errors

public struct RepairRuntimeVMDiskInput: Equatable, Sendable {
    public let rootfsBasePath: String
    public let rootfsBaseState: RuntimePathState
    public let rootfsBaseSizeBytes: UInt64?
    public let currentVMDiskState: RuntimePathState
    public let currentVMDiskSizeBytes: UInt64?
    public let defaultDiskGiB: Int
    public let bytesPerGiB: UInt64
    public let freeSpaceMarginBytes: UInt64

    public init(
        rootfsBasePath: String,
        rootfsBaseState: RuntimePathState,
        rootfsBaseSizeBytes: UInt64?,
        currentVMDiskState: RuntimePathState,
        currentVMDiskSizeBytes: UInt64?,
        defaultDiskGiB: Int,
        bytesPerGiB: UInt64,
        freeSpaceMarginBytes: UInt64
    ) {
        self.rootfsBasePath = rootfsBasePath
        self.rootfsBaseState = rootfsBaseState
        self.rootfsBaseSizeBytes = rootfsBaseSizeBytes
        self.currentVMDiskState = currentVMDiskState
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

public struct RepairRuntimeVMDiskReplacementBuildPlan: Equatable, Sendable {
    public let rootfsBase: URL
    public let vmDiskDirectory: URL
    public let backupsDirectory: URL
    public let temporaryDisk: URL
    public let freeSpaceDirectory: URL
    public let requiredFreeSpaceBytes: UInt64
    public let operation: RuntimeOperation
    public let targetDiskGiB: Int

    public init(
        rootfsBase: URL,
        vmDiskDirectory: URL,
        backupsDirectory: URL,
        temporaryDisk: URL,
        freeSpaceDirectory: URL,
        requiredFreeSpaceBytes: UInt64,
        operation: RuntimeOperation,
        targetDiskGiB: Int
    ) {
        self.rootfsBase = rootfsBase
        self.vmDiskDirectory = vmDiskDirectory
        self.backupsDirectory = backupsDirectory
        self.temporaryDisk = temporaryDisk
        self.freeSpaceDirectory = freeSpaceDirectory
        self.requiredFreeSpaceBytes = requiredFreeSpaceBytes
        self.operation = operation
        self.targetDiskGiB = targetDiskGiB
    }
}

public struct RepairRuntimeVMDiskReplacementObservation: Equatable, Sendable {
    public let path: String
    public let state: RuntimePathState
    public let actualBytes: UInt64?
    public let targetDiskGiB: Int
    public let bytesPerGiB: UInt64

    public init(
        path: String,
        state: RuntimePathState,
        actualBytes: UInt64?,
        targetDiskGiB: Int,
        bytesPerGiB: UInt64
    ) {
        self.path = path
        self.state = state
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

public struct RuntimeVMDiskRepairUseCase {
    public init() {}

    public func planRepair(for input: RepairRuntimeVMDiskInput) throws -> RepairRuntimeVMDiskPlan {
        let rootfsBaseSizeBytes = try requiredRootfsBaseSize(input)
        let currentVMDiskSizeBytes = try currentVMDiskSize(input)
        guard rootfsBaseSizeBytes > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed("rootfs base is empty path=\(input.rootfsBasePath)")
        }
        guard input.defaultDiskGiB > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed("default VM disk size must be positive")
        }
        guard input.bytesPerGiB > 0 else {
            throw RepairRuntimeUseCaseError.operationFailed("bytes per GiB must be positive")
        }

        let requiredFreeSpaceBytes = try requiredFreeSpaceBytes(
            rootfsBaseSizeBytes: rootfsBaseSizeBytes,
            freeSpaceMarginBytes: input.freeSpaceMarginBytes
        )
        return RepairRuntimeVMDiskPlan(
            operation: .repairVMDisk,
            targetDiskGiB: targetDiskGiB(
                currentVMDiskSizeBytes: currentVMDiskSizeBytes,
                defaultDiskGiB: input.defaultDiskGiB,
                bytesPerGiB: input.bytesPerGiB
            ),
            requiredFreeSpaceBytes: requiredFreeSpaceBytes,
            shouldArchiveCurrentDisk: currentVMDiskSizeBytes != nil,
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            )
        )
    }

    private func requiredRootfsBaseSize(_ input: RepairRuntimeVMDiskInput) throws -> UInt64 {
        switch input.rootfsBaseState {
        case .file:
            guard let rootfsBaseSizeBytes = input.rootfsBaseSizeBytes else {
                throw RepairRuntimeUseCaseError.operationFailed(
                    "rootfs base size is missing path=\(input.rootfsBasePath)"
                )
            }
            return rootfsBaseSizeBytes
        case .missing:
            throw RepairRuntimeUseCaseError.operationFailed("missing file: \(input.rootfsBasePath)")
        case .inspectFailed(let reason):
            throw RepairRuntimeUseCaseError.operationFailed(
                "rootfs base path inspection failed: \(input.rootfsBasePath) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw RepairRuntimeUseCaseError.operationFailed(
                "rootfs base path state is unexpected: \(input.rootfsBasePath) state=\(input.rootfsBaseState.rawValue)"
            )
        }
    }

    private func currentVMDiskSize(_ input: RepairRuntimeVMDiskInput) throws -> UInt64? {
        switch input.currentVMDiskState {
        case .file:
            guard let currentVMDiskSizeBytes = input.currentVMDiskSizeBytes else {
                throw RepairRuntimeUseCaseError.operationFailed("current VM disk size is missing")
            }
            return currentVMDiskSizeBytes
        case .missing:
            return nil
        case .inspectFailed(let reason):
            throw RepairRuntimeUseCaseError.operationFailed(
                "current VM disk path inspection failed: \(reason)"
            )
        case .directory, .other, .unknown:
            throw RepairRuntimeUseCaseError.operationFailed(
                "current VM disk path state is unexpected: \(input.currentVMDiskState.rawValue)"
            )
        }
    }

    public func executionPlan(
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

    public func replacementBuildPlan(
        rootfsBase: URL,
        vmDisk: URL,
        backupsDirectory: URL,
        repairPlan: RepairRuntimeVMDiskPlan,
        executionPlan: RepairRuntimeVMDiskExecutionPlan
    ) -> RepairRuntimeVMDiskReplacementBuildPlan {
        RepairRuntimeVMDiskReplacementBuildPlan(
            rootfsBase: rootfsBase,
            vmDiskDirectory: vmDisk.deletingLastPathComponent(),
            backupsDirectory: backupsDirectory,
            temporaryDisk: executionPlan.temporaryDisk,
            freeSpaceDirectory: vmDisk.deletingLastPathComponent(),
            requiredFreeSpaceBytes: repairPlan.requiredFreeSpaceBytes,
            operation: repairPlan.operation,
            targetDiskGiB: repairPlan.targetDiskGiB
        )
    }

    public func requireReplacementDisk(_ observation: RepairRuntimeVMDiskReplacementObservation) throws {
        switch observation.state {
        case .file:
            break
        case .missing:
            throw RepairRuntimeUseCaseError.operationFailed("vm disk repair replacement missing path=\(observation.path)")
        case .inspectFailed(let reason):
            throw RepairRuntimeUseCaseError.operationFailed(
                "vm disk repair replacement path inspection failed: \(observation.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw RepairRuntimeUseCaseError.operationFailed(
                "vm disk repair replacement path state is unexpected: \(observation.path) state=\(observation.state.rawValue)"
            )
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

    public func requestedPlan() -> RepairRuntimeLoggedStatusPlan {
        RepairRuntimeLoggedStatusPlan(
            logMessage: "vm disk repair requested",
            status: .recovering,
            operation: .repairVMDisk,
            statusMessage: "VM disk repair requested"
        )
    }

    public func replacementCreationStatusPlan() -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .recovering,
            operation: .repairVMDisk,
            message: "Creating replacement VM disk"
        )
    }

    public func archiveStatusPlan() -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .recovering,
            operation: .repairVMDisk,
            message: "Archiving current VM disk"
        )
    }

    public func stopServicesFailedStatusPlan(reason: String) -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .critical,
            operation: .repairVMDisk,
            message: "VM disk repair failed before archive; runtime services did not stop. reason=\(reason)"
        )
    }

    public func archivedLogMessage(archivedDiskPath: String) -> String {
        "archived vm disk path=\(archivedDiskPath)"
    }

    public func missingArchiveLogMessage() -> String {
        "vm disk missing; creating replacement without archive"
    }

    public func replacementCreatedLogMessage(vmDiskPath: String, targetDiskGiB: Int) -> String {
        "created replacement vm disk path=\(vmDiskPath) size=\(targetDiskGiB) GiB"
    }

    public func startServicesStatusPlan() -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .recovering,
            operation: .repairVMDisk,
            message: "Starting runtime services after VM disk repair"
        )
    }

    public func completionMessages(archivedDiskPath: String?) -> RepairRuntimeVMDiskCompletionMessages {
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

    public func redisBackupStartedStatusPlan() -> RepairRuntimeStatusPlan {
        RepairRuntimeStatusPlan(
            status: .recovering,
            operation: .repairVMDisk,
            message: "Creating Redis backup before VM disk repair"
        )
    }

    public func redisBackupCompletedPlan() -> RepairRuntimeLoggedStatusPlan {
        RepairRuntimeLoggedStatusPlan(
            logMessage: "redis backup before vm disk repair completed",
            status: .recovering,
            operation: .repairVMDisk,
            statusMessage: "Redis backup completed before VM disk repair"
        )
    }

    public func redisBackupFailedPlan(reason: String) -> RepairRuntimeLoggedStatusPlan {
        RepairRuntimeLoggedStatusPlan(
            logMessage: "redis backup before vm disk repair failed error=\(reason); continuing with VM disk archive",
            status: .recovering,
            operation: .repairVMDisk,
            statusMessage: "Redis backup before VM disk repair failed; current VM disk will be archived before replacement"
        )
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
