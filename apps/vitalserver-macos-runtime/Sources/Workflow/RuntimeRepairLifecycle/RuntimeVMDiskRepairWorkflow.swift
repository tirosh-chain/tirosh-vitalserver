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
    public let pathState: (URL) -> RuntimePathState
    public let fileSize: (URL) throws -> UInt64
    public let createDirectory: (URL, Bool) throws -> Void
    public let removeItem: (URL) throws -> Void
    public let moveItem: (URL, URL) throws -> Void
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let createReplacementVMDisk: (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void
    public let createRedisBackup: () -> RuntimeBestEffortOperationResult
    public let stopRuntimeServicesForVMDiskReplacement: () -> RuntimeBestEffortOperationResult
    public let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let timestamp: () -> String
    public let log: (String) -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        fileSize: @escaping (URL) throws -> UInt64,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        createReplacementVMDisk: @escaping (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void,
        createRedisBackup: @escaping () -> RuntimeBestEffortOperationResult,
        stopRuntimeServicesForVMDiskReplacement: @escaping () -> RuntimeBestEffortOperationResult,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        timestamp: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.pathState = pathState
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
    private let useCase: RuntimeVMDiskRepairUseCase

    public init(useCase: RuntimeVMDiskRepairUseCase = RuntimeVMDiskRepairUseCase()) {
        self.useCase = useCase
    }

    public func repair(
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations
    ) throws {
        let plan = try useCase.planRepair(for: observeRepairInput(context, operations: operations))
        let executionPlan = useCase.executionPlan(
            vmDisk: context.vmDisk,
            backupsDirectory: context.backupsDirectory,
            timestamp: operations.timestamp()
        )
        let buildPlan = useCase.replacementBuildPlan(
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
        let rootfsBaseState = operations.pathState(context.rootfsBase)
        let currentVMDiskState = operations.pathState(context.vmDisk)
        return RepairRuntimeVMDiskInput(
            rootfsBasePath: context.rootfsBase.path,
            rootfsBaseState: rootfsBaseState,
            rootfsBaseSizeBytes: rootfsBaseState == .file ? try operations.fileSize(context.rootfsBase) : nil,
            currentVMDiskState: currentVMDiskState,
            currentVMDiskSizeBytes: currentVMDiskState == .file ? try operations.fileSize(context.vmDisk) : nil,
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
        useCase: RuntimeVMDiskRepairUseCase
    ) throws {
        var archivedDiskPath: String?

        try report(useCase.requestedPlan(), operations: operations)
        try createRedisBackupBestEffort(useCase: useCase, operations: operations)
        try operations.createDirectory(buildPlan.vmDiskDirectory, true)
        try operations.createDirectory(buildPlan.backupsDirectory, true)
        switch operations.pathState(buildPlan.temporaryDisk) {
        case .file, .directory, .other:
            try operations.removeItem(buildPlan.temporaryDisk)
        case .missing:
            break
        case .inspectFailed(let reason):
            throw RepairRuntimeUseCaseError.operationFailed(
                "temporary VM disk path inspection failed: \(buildPlan.temporaryDisk.path) reason=\(reason)"
            )
        case .unknown(let state):
            throw RepairRuntimeUseCaseError.operationFailed(
                "temporary VM disk path state is unexpected: \(buildPlan.temporaryDisk.path) state=\(state)"
            )
        }

        try operations.requireFreeSpace(
            buildPlan.freeSpaceDirectory,
            buildPlan.requiredFreeSpaceBytes,
            buildPlan.operation.rawValue
        )
        try writeStatus(useCase.replacementCreationStatusPlan(), operations: operations)
        try operations.createReplacementVMDisk(buildPlan)

        try writeStatus(useCase.archiveStatusPlan(), operations: operations)
        switch operations.stopRuntimeServicesForVMDiskReplacement() {
        case .completed:
            break
        case .failed(let reason):
            let statusPlan = useCase.stopServicesFailedStatusPlan(reason: reason)
            try writeStatus(
                statusPlan,
                operations: operations
            )
            throw RepairRuntimeUseCaseError.operationFailed(statusPlan.message)
        }
        try operations.createDirectory(executionPlan.archiveDirectory, true)
        if plan.shouldArchiveCurrentDisk {
            try operations.moveItem(context.vmDisk, executionPlan.archivedDisk)
            archivedDiskPath = executionPlan.archivedDisk.path
            operations.log(useCase.archivedLogMessage(archivedDiskPath: executionPlan.archivedDisk.path))
        } else {
            operations.log(useCase.missingArchiveLogMessage())
        }

        try operations.moveItem(executionPlan.temporaryDisk, context.vmDisk)
        try requireReplacementDisk(targetDiskGiB: plan.targetDiskGiB, context: context, operations: operations, useCase: useCase)
        operations.log(useCase.replacementCreatedLogMessage(
            vmDiskPath: context.vmDisk.path,
            targetDiskGiB: plan.targetDiskGiB
        ))

        try writeStatus(useCase.startServicesStatusPlan(), operations: operations)
        try operations.startRuntimeServices(plan.restartPolicy)
        do {
            try operations.waitForHealth(plan.restartPolicy)
            let messages = useCase.completionMessages(archivedDiskPath: archivedDiskPath)
            try operations.writeStatus(.healthy, .repairVMDisk, messages.healthy)
        } catch {
            let messages = useCase.completionMessages(archivedDiskPath: archivedDiskPath)
            try operations.writeStatus(.degraded, .repairVMDisk, messages.degraded)
            throw error
        }
    }

    private func requireReplacementDisk(
        targetDiskGiB: Int,
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations,
        useCase: RuntimeVMDiskRepairUseCase
    ) throws {
        let state = operations.pathState(context.vmDisk)
        try useCase.requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: context.vmDisk.path,
            state: state,
            actualBytes: state == .file ? try operations.fileSize(context.vmDisk) : nil,
            targetDiskGiB: targetDiskGiB,
            bytesPerGiB: context.bytesPerGiB
        ))
    }

    private func createRedisBackupBestEffort(
        useCase: RuntimeVMDiskRepairUseCase,
        operations: RuntimeVMDiskRepairOperations
    ) throws {
        try writeStatus(useCase.redisBackupStartedStatusPlan(), operations: operations)
        switch operations.createRedisBackup() {
        case .completed:
            try report(useCase.redisBackupCompletedPlan(), operations: operations)
        case .failed(let reason):
            try report(
                useCase.redisBackupFailedPlan(reason: reason),
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
