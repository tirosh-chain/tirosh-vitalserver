import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Workflow
import Errors

public struct RuntimeVMDiskRepairCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(installedPaths: InstalledRuntimePaths) {
        self.installedPaths = installedPaths
    }
}

public struct RuntimeVMDiskRepairCompositionOperations {
    let fileStore: RuntimeFileStore
    let requireFreeSpace: (URL, UInt64, String) throws -> Void
    let runProcessToFile: (String, [String], URL) throws -> Void
    let runRequired: (String, [String]) throws -> Void
    let createRedisBackup: () throws -> Void
    let stopRuntimeServicesForVMDiskReplacement: () throws -> Void
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let timestamp: () -> String
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
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
        self.fileStore = fileStore
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

public enum RuntimeVMDiskRepairComposition {
    public static func make(
        context: RuntimeVMDiskRepairCompositionContext,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) -> RuntimeVMDiskRepairRunner {
        let runnerContext = RuntimeVMDiskRepairContext(
            rootfsBase: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
            vmDisk: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
            backupsDirectory: context.installedPaths.backupsDirectory,
            defaultDiskGiB: Constants.Defaults.defaultDiskGiB,
            freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes,
            gunzipExecutable: Constants.Commands.gunzip,
            truncateExecutable: Constants.Commands.truncate
        )
        return RuntimeVMDiskRepairRunner(
            context: runnerContext,
            operations: RuntimeVMDiskRepairOperations(
                observeRepairInput: { repairContext in
                    try observeRepairInput(repairContext, fileStore: operations.fileStore)
                },
                executeRepairPlan: { plan, executionPlan, buildPlan in
                    try executeRepairPlan(
                        plan,
                        executionPlan: executionPlan,
                        buildPlan: buildPlan,
                        context: runnerContext,
                        operations: operations
                    )
                },
                timestamp: operations.timestamp
            )
        )
    }

    private static func observeRepairInput(
        _ context: RuntimeVMDiskRepairContext,
        fileStore: RuntimeFileStore
    ) throws -> RepairRuntimeVMDiskInput {
        let rootfsBaseExists = fileStore.fileExists(context.rootfsBase)
        let rootfsBaseSizeBytes = rootfsBaseExists ? try fileStore.fileSize(context.rootfsBase) : 0
        let currentVMDiskSizeBytes: UInt64?
        if fileStore.fileExists(context.vmDisk) {
            currentVMDiskSizeBytes = try fileStore.fileSize(context.vmDisk)
        } else {
            currentVMDiskSizeBytes = nil
        }
        return RepairRuntimeVMDiskInput(
            rootfsBasePath: context.rootfsBase.path,
            rootfsBaseExists: rootfsBaseExists,
            rootfsBaseSizeBytes: rootfsBaseSizeBytes,
            currentVMDiskSizeBytes: currentVMDiskSizeBytes,
            defaultDiskGiB: context.defaultDiskGiB,
            bytesPerGiB: context.bytesPerGiB,
            freeSpaceMarginBytes: context.freeSpaceMarginBytes
        )
    }

    private static func executeRepairPlan(
        _ plan: RepairRuntimeVMDiskPlan,
        executionPlan: RepairRuntimeVMDiskExecutionPlan,
        buildPlan: RepairRuntimeVMDiskReplacementBuildPlan,
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) throws {
        let useCase = RepairRuntimeUseCase()
        var archivedDiskPath: String?

        try report(useCase.vmDiskRepairRequestedPlan(), operations: operations)
        try createRedisBackupBestEffort(useCase: useCase, operations: operations)
        try operations.fileStore.createDirectory(at: buildPlan.vmDiskDirectory, withIntermediateDirectories: true)
        try operations.fileStore.createDirectory(at: buildPlan.backupsDirectory, withIntermediateDirectories: true)
        if operations.fileStore.fileExists(buildPlan.temporaryDisk) {
            try operations.fileStore.removeItem(at: buildPlan.temporaryDisk)
        }

        try operations.requireFreeSpace(
            buildPlan.freeSpaceDirectory,
            buildPlan.requiredFreeSpaceBytes,
            buildPlan.operation.rawValue
        )
        try writeStatus(useCase.vmDiskReplacementCreationStatusPlan(), operations: operations)
        try operations.runProcessToFile(
            buildPlan.decompression.executable,
            buildPlan.decompression.arguments,
            buildPlan.decompression.output
        )
        try operations.runRequired(buildPlan.resize.executable, buildPlan.resize.arguments)

        try writeStatus(useCase.vmDiskArchiveStatusPlan(), operations: operations)
        try operations.stopRuntimeServicesForVMDiskReplacement()
        try operations.fileStore.createDirectory(at: executionPlan.archiveDirectory, withIntermediateDirectories: true)
        if plan.shouldArchiveCurrentDisk {
            try operations.fileStore.moveItem(at: context.vmDisk, to: executionPlan.archivedDisk)
            archivedDiskPath = executionPlan.archivedDisk.path
            operations.log(useCase.vmDiskArchivedLogMessage(archivedDiskPath: executionPlan.archivedDisk.path))
        } else {
            operations.log(useCase.vmDiskMissingArchiveLogMessage())
        }

        try operations.fileStore.moveItem(at: executionPlan.temporaryDisk, to: context.vmDisk)
        try requireReplacementDisk(targetDiskGiB: plan.targetDiskGiB, context: context, operations: operations)
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

    private static func requireReplacementDisk(
        targetDiskGiB: Int,
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) throws {
        let exists = operations.fileStore.fileExists(context.vmDisk)
        try RepairRuntimeUseCase().requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: context.vmDisk.path,
            exists: exists,
            actualBytes: exists ? try operations.fileStore.fileSize(context.vmDisk) : nil,
            targetDiskGiB: targetDiskGiB,
            bytesPerGiB: context.bytesPerGiB
        ))
    }

    private static func createRedisBackupBestEffort(
        useCase: RepairRuntimeUseCase,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) throws {
        try writeStatus(useCase.vmDiskRedisBackupStartedStatusPlan(), operations: operations)
        do {
            try operations.createRedisBackup()
            try report(useCase.vmDiskRedisBackupCompletedPlan(), operations: operations)
        } catch {
            try report(useCase.vmDiskRedisBackupFailedPlan(reason: error.localizedDescription), operations: operations)
        }
    }

    private static func report(
        _ plan: RepairRuntimeLoggedStatusPlan,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) throws {
        operations.log(plan.logMessage)
        try operations.writeStatus(plan.status, plan.operation, plan.statusMessage)
    }

    private static func writeStatus(
        _ plan: RepairRuntimeStatusPlan,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) throws {
        try operations.writeStatus(plan.status, plan.operation, plan.message)
    }
}
