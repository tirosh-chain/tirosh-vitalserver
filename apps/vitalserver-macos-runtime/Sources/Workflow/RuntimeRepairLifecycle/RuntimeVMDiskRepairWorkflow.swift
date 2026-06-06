import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeVMDiskRepairContext {
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

public struct RuntimeVMDiskRepairOperations {
    public let fileExists: (URL) -> Bool
    public let fileSize: (URL) throws -> UInt64
    public let createDirectory: (URL, Bool) throws -> Void
    public let removeItem: (URL) throws -> Void
    public let moveItem: (URL, URL) throws -> Void
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let runProcessToFile: (String, [String], URL) throws -> Void
    public let runRequired: (String, [String]) throws -> Void
    public let createRedisBackup: () throws -> Void
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
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        runRequired: @escaping (String, [String]) throws -> Void,
        createRedisBackup: @escaping () throws -> Void,
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
        self.runProcessToFile = runProcessToFile
        self.runRequired = runRequired
        self.createRedisBackup = createRedisBackup
        self.stopRuntimeServicesForVMDiskReplacement = stopRuntimeServicesForVMDiskReplacement
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.timestamp = timestamp
        self.log = log
    }
}

public struct RuntimeVMDiskRepairRunner {
    public let context: RuntimeVMDiskRepairContext
    public let operations: RuntimeVMDiskRepairOperations
    public let useCase: RepairRuntimeUseCase

    public init(
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations,
        useCase: RepairRuntimeUseCase = RepairRuntimeUseCase()
    ) {
        self.context = context
        self.operations = operations
        self.useCase = useCase
    }

    public func repair() throws {
        let plan = try repairPlan()
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
        var archivedDiskPath: String?

        try report(useCase.vmDiskRepairRequestedPlan())
        try createRedisBackupBestEffort()
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
        try writeStatus(useCase.vmDiskReplacementCreationStatusPlan())
        try operations.runProcessToFile(
            buildPlan.decompression.executable,
            buildPlan.decompression.arguments,
            buildPlan.decompression.output
        )
        try operations.runRequired(buildPlan.resize.executable, buildPlan.resize.arguments)

        try writeStatus(useCase.vmDiskArchiveStatusPlan())
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
        try requireReplacementDisk(targetDiskGiB: plan.targetDiskGiB)
        operations.log(useCase.vmDiskReplacementCreatedLogMessage(
            vmDiskPath: context.vmDisk.path,
            targetDiskGiB: plan.targetDiskGiB
        ))

        try writeStatus(useCase.vmDiskStartServicesStatusPlan())
        try operations.startRuntimeServices(plan.restartPolicy)
        do {
            try operations.waitForHealth(plan.restartPolicy)
            let messages = useCase.vmDiskCompletionMessages(archivedDiskPath: archivedDiskPath)
            try operations.writeStatus(
                .healthy,
                .repairVMDisk,
                messages.healthy
            )
        } catch {
            let messages = useCase.vmDiskCompletionMessages(archivedDiskPath: archivedDiskPath)
            try operations.writeStatus(
                .degraded,
                .repairVMDisk,
                messages.degraded
            )
            throw error
        }
    }

    private func repairPlan() throws -> RepairRuntimeVMDiskPlan {
        let rootfsBaseExists = operations.fileExists(context.rootfsBase)
        let rootfsBaseSizeBytes = rootfsBaseExists ? try operations.fileSize(context.rootfsBase) : 0
        let currentVMDiskSizeBytes: UInt64?
        if operations.fileExists(context.vmDisk) {
            currentVMDiskSizeBytes = try operations.fileSize(context.vmDisk)
        } else {
            currentVMDiskSizeBytes = nil
        }
        return try useCase.planVMDiskRepair(for: RepairRuntimeVMDiskInput(
            rootfsBasePath: context.rootfsBase.path,
            rootfsBaseExists: rootfsBaseExists,
            rootfsBaseSizeBytes: rootfsBaseSizeBytes,
            currentVMDiskSizeBytes: currentVMDiskSizeBytes,
            defaultDiskGiB: context.defaultDiskGiB,
            bytesPerGiB: context.bytesPerGiB,
            freeSpaceMarginBytes: context.freeSpaceMarginBytes
        ))
    }

    private func requireReplacementDisk(targetDiskGiB: Int) throws {
        let exists = operations.fileExists(context.vmDisk)
        try useCase.requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: context.vmDisk.path,
            exists: exists,
            actualBytes: exists ? try operations.fileSize(context.vmDisk) : nil,
            targetDiskGiB: targetDiskGiB,
            bytesPerGiB: context.bytesPerGiB
        ))
    }

    private func createRedisBackupBestEffort() throws {
        try writeStatus(useCase.vmDiskRedisBackupStartedStatusPlan())
        do {
            try operations.createRedisBackup()
            try report(useCase.vmDiskRedisBackupCompletedPlan())
        } catch {
            try report(useCase.vmDiskRedisBackupFailedPlan(reason: error.localizedDescription))
        }
    }

    private func report(_ plan: RepairRuntimeLoggedStatusPlan) throws {
        operations.log(plan.logMessage)
        try operations.writeStatus(plan.status, plan.operation, plan.statusMessage)
    }

    private func writeStatus(_ plan: RepairRuntimeStatusPlan) throws {
        try operations.writeStatus(plan.status, plan.operation, plan.message)
    }

}
