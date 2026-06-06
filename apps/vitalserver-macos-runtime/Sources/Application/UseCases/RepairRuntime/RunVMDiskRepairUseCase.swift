import Foundation
import Contracts
import Domain

public struct RunVMDiskRepairUseCase {
    public init() {}

    public func repair(
        context: RunVMDiskRepairContext,
        operations: RunVMDiskRepairOperations
    ) throws {
        let useCase = RepairRuntimeUseCase()
        let plan = try useCase.planVMDiskRepair(for: operations.observeRepairInput(context))
        let executionPlan = useCase.vmDiskExecutionPlan(
            vmDisk: context.vmDisk,
            backupsDirectory: context.backupsDirectory,
            timestamp: operations.timestamp()
        )
        let buildPlan = useCase.vmDiskReplacementBuildPlan(
            rootfsBase: context.rootfsBase,
            vmDisk: context.vmDisk,
            backupsDirectory: context.backupsDirectory,
            gunzipExecutable: context.gunzipExecutable,
            truncateExecutable: context.truncateExecutable,
            repairPlan: plan,
            executionPlan: executionPlan
        )
        try operations.executeRepairPlan(plan, executionPlan, buildPlan)
    }
}

public struct RunVMDiskRepairContext {
    public let rootfsBase: URL
    public let vmDisk: URL
    public let backupsDirectory: URL
    public let defaultDiskGiB: Int
    public let bytesPerGiB: UInt64
    public let freeSpaceMarginBytes: UInt64
    public let gunzipExecutable: String
    public let truncateExecutable: String

    public init(
        rootfsBase: URL,
        vmDisk: URL,
        backupsDirectory: URL,
        defaultDiskGiB: Int,
        bytesPerGiB: UInt64 = 1024 * 1024 * 1024,
        freeSpaceMarginBytes: UInt64,
        gunzipExecutable: String,
        truncateExecutable: String
    ) {
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.backupsDirectory = backupsDirectory
        self.defaultDiskGiB = defaultDiskGiB
        self.bytesPerGiB = bytesPerGiB
        self.freeSpaceMarginBytes = freeSpaceMarginBytes
        self.gunzipExecutable = gunzipExecutable
        self.truncateExecutable = truncateExecutable
    }
}

public struct RunVMDiskRepairOperations {
    public let observeRepairInput: (RunVMDiskRepairContext) throws -> RepairRuntimeVMDiskInput
    public let executeRepairPlan: (
        RepairRuntimeVMDiskPlan,
        RepairRuntimeVMDiskExecutionPlan,
        RepairRuntimeVMDiskReplacementBuildPlan
    ) throws -> Void
    public let timestamp: () -> String

    public init(
        observeRepairInput: @escaping (RunVMDiskRepairContext) throws -> RepairRuntimeVMDiskInput,
        executeRepairPlan: @escaping (
            RepairRuntimeVMDiskPlan,
            RepairRuntimeVMDiskExecutionPlan,
            RepairRuntimeVMDiskReplacementBuildPlan
        ) throws -> Void,
        timestamp: @escaping () -> String
    ) {
        self.observeRepairInput = observeRepairInput
        self.executeRepairPlan = executeRepairPlan
        self.timestamp = timestamp
    }
}
