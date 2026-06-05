import Contracts
import Core
import Foundation

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

    public init(
        context: RuntimeVMDiskRepairContext,
        operations: RuntimeVMDiskRepairOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func repair() throws {
        guard operations.fileExists(context.rootfsBase) else {
            throw RuntimeWorkflowError.operationFailed("missing file: \(context.rootfsBase.path)")
        }

        let targetDiskGiB = try targetDiskGiB()
        let temporaryDisk = context.vmDisk.deletingLastPathComponent()
            .appendingPathComponent(".\(context.vmDisk.lastPathComponent).repair.tmp")
        let archiveDirectory = context.backupsDirectory
            .appendingPathComponent("vm-disk-repair-\(sanitizedTimestamp())")
        let archivedDisk = archiveDirectory.appendingPathComponent(context.vmDisk.lastPathComponent)
        let restartPolicy = RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: true)
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
            context.gunzipExecutable,
            ["-c", context.rootfsBase.path],
            temporaryDisk
        )
        try operations.runRequired(context.truncateExecutable, ["-s", "\(targetDiskGiB)G", temporaryDisk.path])

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
        try requireReplacementDisk(targetDiskGiB: targetDiskGiB)
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

    private func requireReplacementDisk(targetDiskGiB: Int) throws {
        guard operations.fileExists(context.vmDisk) else {
            throw RuntimeWorkflowError.operationFailed("vm disk repair replacement missing path=\(context.vmDisk.path)")
        }
        let expectedBytes = UInt64(targetDiskGiB) * context.bytesPerGiB
        let actualBytes = try operations.fileSize(context.vmDisk)
        guard actualBytes >= expectedBytes else {
            throw RuntimeWorkflowError.operationFailed(
                "vm disk repair replacement undersized path=\(context.vmDisk.path) expectedBytes=\(expectedBytes) actualBytes=\(actualBytes)"
            )
        }
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
