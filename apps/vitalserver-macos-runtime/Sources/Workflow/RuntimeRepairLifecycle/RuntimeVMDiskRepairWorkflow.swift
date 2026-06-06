import Application
import Contracts
import Domain
import Foundation

public struct RuntimeVMDiskRepairContext: Equatable, Sendable {
    public let rootfsBase: URL
    public let vmDisk: URL
    public let backupsDirectory: URL
    public let defaultDiskGiB: Int
    public let bytesPerGiB: UInt64
    public let freeSpaceMarginBytes: UInt64

    public init(
        rootfsBase: URL,
        vmDisk: URL,
        backupsDirectory: URL,
        defaultDiskGiB: Int,
        bytesPerGiB: UInt64 = 1024 * 1024 * 1024,
        freeSpaceMarginBytes: UInt64
    ) {
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.backupsDirectory = backupsDirectory
        self.defaultDiskGiB = defaultDiskGiB
        self.bytesPerGiB = bytesPerGiB
        self.freeSpaceMarginBytes = freeSpaceMarginBytes
    }
}

public struct RuntimeVMDiskRepairOperations {
    public let fileExists: (URL) -> Bool
    public let fileSize: (URL) throws -> UInt64
    public let createDirectory: (URL, Bool) throws -> Void
    public let removeItem: (URL) throws -> Void
    public let moveItem: (URL, URL) throws -> Void
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let createReplacementVMDisk: (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void
    public let createRedisBackup: () -> RuntimeBestEffortOperationResult
    public let stopRuntimeServicesForVMDiskReplacement: () throws -> Void
    public let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let timestamp: () -> String
    public let log: (String) -> Void

    public init(
        fileExists: @escaping (URL) -> Bool,
        fileSize: @escaping (URL) throws -> UInt64,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        createReplacementVMDisk: @escaping (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void,
        createRedisBackup: @escaping () -> RuntimeBestEffortOperationResult,
        stopRuntimeServicesForVMDiskReplacement: @escaping () throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        timestamp: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.fileExists = fileExists
        self.fileSize = fileSize
        self.createDirectory = createDirectory
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.requireFreeSpace = requireFreeSpace
        self.createReplacementVMDisk = createReplacementVMDisk
        self.createRedisBackup = createRedisBackup
        self.stopRuntimeServicesForVMDiskReplacement = stopRuntimeServicesForVMDiskReplacement
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.timestamp = timestamp
        self.log = log
    }
}

public struct RuntimeVMDiskRepairWorkflow {
    public init() {}

    public func repair(
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations
    ) throws {
        let useCase = RepairRuntimeUseCase()
        let plan = try useCase.planVMDiskRepair(for: observeRepairInput(context, operations: operations))
        let executionPlan = useCase.vmDiskExecutionPlan(
            vmDisk: context.vmDisk,
            backupsDirectory: context.backupsDirectory,
            timestamp: operations.timestamp()
        )
        let buildPlan = useCase.vmDiskReplacementBuildPlan(
            rootfsBase: context.rootfsBase,
            vmDisk: context.vmDisk,
            backupsDirectory: context.backupsDirectory,
            repairPlan: plan,
            executionPlan: executionPlan
        )
        try executeRepairPlan(
            plan,
            executionPlan: executionPlan,
            buildPlan: buildPlan,
            context: context,
            operations: operations,
            useCase: useCase
        )
    }

    private func observeRepairInput(
        _ context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations
    ) throws -> RepairRuntimeVMDiskInput {
        let rootfsBaseExists = operations.fileExists(context.rootfsBase)
        let currentVMDiskSizeBytes: UInt64?
        if operations.fileExists(context.vmDisk) {
            currentVMDiskSizeBytes = try operations.fileSize(context.vmDisk)
        } else {
            currentVMDiskSizeBytes = nil
        }
        return RepairRuntimeVMDiskInput(
            rootfsBasePath: context.rootfsBase.path,
            rootfsBaseExists: rootfsBaseExists,
            rootfsBaseSizeBytes: rootfsBaseExists ? try operations.fileSize(context.rootfsBase) : 0,
            currentVMDiskSizeBytes: currentVMDiskSizeBytes,
            defaultDiskGiB: context.defaultDiskGiB,
            bytesPerGiB: context.bytesPerGiB,
            freeSpaceMarginBytes: context.freeSpaceMarginBytes
        )
    }

    private func executeRepairPlan(
        _ plan: RepairRuntimeVMDiskPlan,
        executionPlan: RepairRuntimeVMDiskExecutionPlan,
        buildPlan: RepairRuntimeVMDiskReplacementBuildPlan,
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations,
        useCase: RepairRuntimeUseCase
    ) throws {
        var archivedDiskPath: String?

        try report(useCase.vmDiskRepairRequestedPlan(), operations: operations)
        try createRedisBackupBestEffort(useCase: useCase, operations: operations)
        try operations.createDirectory(buildPlan.vmDiskDirectory, true)
        try operations.createDirectory(buildPlan.backupsDirectory, true)
        if operations.fileExists(buildPlan.temporaryDisk) {
            try operations.removeItem(buildPlan.temporaryDisk)
        }

        try operations.requireFreeSpace(
            buildPlan.freeSpaceDirectory,
            buildPlan.requiredFreeSpaceBytes,
            buildPlan.operation.rawValue
        )
        try writeStatus(useCase.vmDiskReplacementCreationStatusPlan(), operations: operations)
        try operations.createReplacementVMDisk(buildPlan)

        try writeStatus(useCase.vmDiskArchiveStatusPlan(), operations: operations)
        try operations.stopRuntimeServicesForVMDiskReplacement()
        try operations.createDirectory(executionPlan.archiveDirectory, true)
        if plan.shouldArchiveCurrentDisk {
            try operations.moveItem(context.vmDisk, executionPlan.archivedDisk)
            archivedDiskPath = executionPlan.archivedDisk.path
            operations.log(useCase.vmDiskArchivedLogMessage(archivedDiskPath: executionPlan.archivedDisk.path))
        } else {
            operations.log(useCase.vmDiskMissingArchiveLogMessage())
        }

        try operations.moveItem(executionPlan.temporaryDisk, context.vmDisk)
        try requireReplacementDisk(targetDiskGiB: plan.targetDiskGiB, context: context, operations: operations, useCase: useCase)
        operations.log(useCase.vmDiskReplacementCreatedLogMessage(
            vmDiskPath: context.vmDisk.path,
            targetDiskGiB: plan.targetDiskGiB
        ))

        try writeStatus(useCase.vmDiskStartServicesStatusPlan(), operations: operations)
        try operations.startRuntimeServices(plan.restartPolicy)
        do {
            try operations.waitForHealth(plan.restartPolicy)
            let messages = useCase.vmDiskCompletionMessages(archivedDiskPath: archivedDiskPath)
            try operations.writeStatus(.healthy, .repairVMDisk, messages.healthy)
        } catch {
            let messages = useCase.vmDiskCompletionMessages(archivedDiskPath: archivedDiskPath)
            try operations.writeStatus(.degraded, .repairVMDisk, messages.degraded)
            throw error
        }
    }

    private func requireReplacementDisk(
        targetDiskGiB: Int,
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations,
        useCase: RepairRuntimeUseCase
    ) throws {
        let exists = operations.fileExists(context.vmDisk)
        try useCase.requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: context.vmDisk.path,
            exists: exists,
            actualBytes: exists ? try operations.fileSize(context.vmDisk) : nil,
            targetDiskGiB: targetDiskGiB,
            bytesPerGiB: context.bytesPerGiB
        ))
    }

    private func createRedisBackupBestEffort(
        useCase: RepairRuntimeUseCase,
        operations: RuntimeVMDiskRepairOperations
    ) throws {
        try writeStatus(useCase.vmDiskRedisBackupStartedStatusPlan(), operations: operations)
        switch operations.createRedisBackup() {
        case .completed:
            try report(useCase.vmDiskRedisBackupCompletedPlan(), operations: operations)
        case .failed(let reason):
            try report(
                useCase.vmDiskRedisBackupFailedPlan(reason: reason),
                operations: operations
            )
        }
    }

    private func report(
        _ plan: RepairRuntimeLoggedStatusPlan,
        operations: RuntimeVMDiskRepairOperations
    ) throws {
        operations.log(plan.logMessage)
        try operations.writeStatus(plan.status, plan.operation, plan.statusMessage)
    }

    private func writeStatus(
        _ plan: RepairRuntimeStatusPlan,
        operations: RuntimeVMDiskRepairOperations
    ) throws {
        try operations.writeStatus(plan.status, plan.operation, plan.message)
    }
}
