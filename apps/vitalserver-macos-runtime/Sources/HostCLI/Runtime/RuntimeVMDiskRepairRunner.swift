import Foundation
import Core
import Contracts

struct RuntimeVMDiskRepairContext {
    let rootfsBase: URL
    let vmDisk: URL
    let backupsDirectory: URL
    let defaultDiskGiB: Int
    let bytesPerGiB: UInt64
    let freeSpaceMarginBytes: UInt64

    init(
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

struct RuntimeVMDiskRepairOperations {
    let fileExists: (URL) -> Bool
    let fileSize: (URL) throws -> UInt64
    let createDirectory: (URL, Bool) throws -> Void
    let removeItem: (URL) throws -> Void
    let moveItem: (URL, URL) throws -> Void
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
}

struct RuntimeVMDiskRepairRunner {
    let context: RuntimeVMDiskRepairContext
    let operations: RuntimeVMDiskRepairOperations

    func repair() throws {
        guard operations.fileExists(context.rootfsBase) else {
            throw LauncherError.missingFile(context.rootfsBase.path)
        }

        let targetDiskGiB = try targetDiskGiB()
        let temporaryDisk = context.vmDisk.deletingLastPathComponent()
            .appendingPathComponent(".\(context.vmDisk.lastPathComponent).repair.tmp")
        let archiveDirectory = context.backupsDirectory
            .appendingPathComponent("vm-disk-repair-\(sanitizedTimestamp())")
        let archivedDisk = archiveDirectory.appendingPathComponent(context.vmDisk.lastPathComponent)
        let restartPolicy = RuntimeServiceRestartPolicy(restartVM: true, restartProxy: true, restartWatchdog: true)
        var archivedDiskPath: String?

        operations.log("vm disk repair requested")
        try operations.writeStatus(.recovering, .repairVMDisk, "VM disk repair requested")
        try createRedisBackupBestEffort()
        try operations.createDirectory(context.vmDisk.deletingLastPathComponent(), true)
        try operations.createDirectory(context.backupsDirectory, true)
        if operations.fileExists(temporaryDisk) {
            try operations.removeItem(temporaryDisk)
        }

        try operations.requireFreeSpace(
            context.vmDisk.deletingLastPathComponent(),
            (try operations.fileSize(context.rootfsBase) * 6) + context.freeSpaceMarginBytes,
            RuntimeOperation.repairVMDisk.rawValue
        )
        try operations.writeStatus(.recovering, .repairVMDisk, "Creating replacement VM disk")
        try operations.runProcessToFile(
            Constants.Commands.gunzip,
            ["-c", context.rootfsBase.path],
            temporaryDisk
        )
        try operations.runRequired(Constants.Commands.truncate, ["-s", "\(targetDiskGiB)G", temporaryDisk.path])

        try operations.writeStatus(.recovering, .repairVMDisk, "Archiving current VM disk")
        try operations.stopRuntimeServicesForVMDiskReplacement()
        try operations.createDirectory(archiveDirectory, true)
        if operations.fileExists(context.vmDisk) {
            try operations.moveItem(context.vmDisk, archivedDisk)
            archivedDiskPath = archivedDisk.path
            operations.log("archived vm disk path=\(archivedDisk.path)")
        } else {
            operations.log("vm disk missing; creating replacement without archive")
        }

        try operations.moveItem(temporaryDisk, context.vmDisk)
        operations.log("created replacement vm disk path=\(context.vmDisk.path) size=\(targetDiskGiB) GiB")

        try operations.writeStatus(.recovering, .repairVMDisk, "Starting runtime services after VM disk repair")
        try operations.startRuntimeServices(restartPolicy)
        do {
            try operations.waitForHealth(restartPolicy)
            try operations.writeStatus(
                .healthy,
                .repairVMDisk,
                completionMessage(archivedDiskPath: archivedDiskPath)
            )
        } catch {
            try operations.writeStatus(
                .degraded,
                .repairVMDisk,
                failedHealthMessage(archivedDiskPath: archivedDiskPath)
            )
            throw error
        }
    }

    private func targetDiskGiB() throws -> Int {
        guard operations.fileExists(context.vmDisk) else {
            return context.defaultDiskGiB
        }
        let currentBytes = try operations.fileSize(context.vmDisk)
        let currentGiB = Int((currentBytes + context.bytesPerGiB - 1) / context.bytesPerGiB)
        return max(context.defaultDiskGiB, currentGiB)
    }

    private func sanitizedTimestamp() -> String {
        operations.timestamp()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func createRedisBackupBestEffort() throws {
        try operations.writeStatus(.recovering, .repairVMDisk, "Creating Redis backup before VM disk repair")
        do {
            try operations.createRedisBackup()
            operations.log("redis backup before vm disk repair completed")
            try operations.writeStatus(.recovering, .repairVMDisk, "Redis backup completed before VM disk repair")
        } catch {
            operations.log("redis backup before vm disk repair failed error=\(error.localizedDescription); continuing with VM disk archive")
            try operations.writeStatus(
                .recovering,
                .repairVMDisk,
                "Redis backup before VM disk repair failed; current VM disk will be archived before replacement"
            )
        }
    }

    private func completionMessage(archivedDiskPath: String?) -> String {
        guard let archivedDiskPath else {
            return "VM disk repaired."
        }
        return "VM disk repaired. Previous disk archive: \(archivedDiskPath)"
    }

    private func failedHealthMessage(archivedDiskPath: String?) -> String {
        guard let archivedDiskPath else {
            return "VM disk was recreated, but runtime health check failed."
        }
        return "VM disk was recreated, but runtime health check failed. Previous disk archive: \(archivedDiskPath)"
    }
}
