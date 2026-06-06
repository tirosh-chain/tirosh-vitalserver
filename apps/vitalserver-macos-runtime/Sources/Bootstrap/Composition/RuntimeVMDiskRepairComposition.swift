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
        RuntimeVMDiskRepairRunner(
            context: RuntimeVMDiskRepairContext(
                rootfsBase: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
                vmDisk: context.installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
                backupsDirectory: context.installedPaths.backupsDirectory,
                defaultDiskGiB: Constants.Defaults.defaultDiskGiB,
                freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes,
                gunzipExecutable: Constants.Commands.gunzip,
                truncateExecutable: Constants.Commands.truncate
            ),
            operations: RuntimeVMDiskRepairOperations(
                fileExists: operations.fileStore.fileExists,
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
                runProcessToFile: operations.runProcessToFile,
                runRequired: operations.runRequired,
                createRedisBackup: operations.createRedisBackup,
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
