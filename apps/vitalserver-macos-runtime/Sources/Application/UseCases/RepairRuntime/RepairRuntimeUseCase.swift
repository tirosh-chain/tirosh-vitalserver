import Contracts
import Domain
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
}
