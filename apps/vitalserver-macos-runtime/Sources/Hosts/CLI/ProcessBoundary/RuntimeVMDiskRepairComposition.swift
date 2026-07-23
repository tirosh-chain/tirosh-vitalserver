import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Workflow

public struct RuntimeVMDiskRepairCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(installedPaths: InstalledRuntimePaths) {
        self.installedPaths = installedPaths
    }
}

public struct RuntimeVMDiskRepairCompositionOperations {
    let fileStore: RuntimeFileStore
    let requireFreeSpace: (URL, UInt64, String) throws -> Void
    let createReplacementVMDisk: (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void
    let createVitalServerBackup: () -> RuntimeBestEffortOperationResult
    let stopRuntimeServicesForVMDiskReplacement: () -> RuntimeBestEffortOperationResult
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let timestamp: () -> String
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        createReplacementVMDisk: @escaping (RepairRuntimeVMDiskReplacementBuildPlan) throws -> Void,
        createVitalServerBackup: @escaping () -> RuntimeBestEffortOperationResult,
        stopRuntimeServicesForVMDiskReplacement: @escaping () -> RuntimeBestEffortOperationResult,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        timestamp: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.requireFreeSpace = requireFreeSpace
        self.createReplacementVMDisk = createReplacementVMDisk
        self.createVitalServerBackup = createVitalServerBackup
        self.stopRuntimeServicesForVMDiskReplacement = stopRuntimeServicesForVMDiskReplacement
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.timestamp = timestamp
        self.log = log
    }
}

public struct RuntimeVMDiskRepairComposition {
    let context: RuntimeVMDiskRepairCompositionContext
    let operations: RuntimeVMDiskRepairCompositionOperations

    public init(
        context: RuntimeVMDiskRepairCompositionContext,
        operations: RuntimeVMDiskRepairCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func repair() throws {
        let repairContext = RuntimeVMDiskRepairContext(
            rootfsBase: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
            vmDisk: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
            backupsDirectory: context.installedPaths.backupsDirectory,
            defaultDiskGiB: Constants.Defaults.defaultDiskGiB,
            freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes
        )
        try RuntimeVMDiskRepairWorkflow().repair(
            context: repairContext,
            operations: RuntimeVMDiskRepairOperations(
                pathState: operations.fileStore.pathState,
                fileSize: operations.fileStore.fileSize,
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                },
                moveItem: { source, destination in
                    try operations.fileStore.moveItem(at: source, to: destination)
                },
                requireFreeSpace: operations.requireFreeSpace,
                createReplacementVMDisk: operations.createReplacementVMDisk,
                createVitalServerBackup: operations.createVitalServerBackup,
                stopRuntimeServicesForVMDiskReplacement: operations.stopRuntimeServicesForVMDiskReplacement,
                startRuntimeServices: operations.startRuntimeServices,
                waitForHealth: operations.waitForHealth,
                writeStatus: operations.writeStatus,
                timestamp: operations.timestamp,
                log: operations.log
            )
        )
    }
}
