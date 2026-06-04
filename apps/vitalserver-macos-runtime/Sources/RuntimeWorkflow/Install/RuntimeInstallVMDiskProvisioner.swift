import Foundation

public struct RuntimeInstallVMDiskProvisioningContext {
    public let rootfsBase: URL
    public let vmDisk: URL
    public let gunzipExecutable: String
    public let truncateExecutable: String
    public let freeSpaceMarginBytes: UInt64

    public init(
        rootfsBase: URL,
        vmDisk: URL,
        gunzipExecutable: String,
        truncateExecutable: String,
        freeSpaceMarginBytes: UInt64
    ) {
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.gunzipExecutable = gunzipExecutable
        self.truncateExecutable = truncateExecutable
        self.freeSpaceMarginBytes = freeSpaceMarginBytes
    }
}

public struct RuntimeInstallVMDiskProvisioningOperations {
    public let fileExists: (URL) -> Bool
    public let fileSize: (URL) throws -> UInt64
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let removeItem: (URL) throws -> Void
    public let runProcessToFile: (String, [String], URL) throws -> Void
    public let moveItem: (URL, URL) throws -> Void
    public let runRequired: (String, [String]) throws -> Void
    public let log: (String) -> Void

    public init(
        fileExists: @escaping (URL) -> Bool,
        fileSize: @escaping (URL) throws -> UInt64,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        runRequired: @escaping (String, [String]) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileExists = fileExists
        self.fileSize = fileSize
        self.requireFreeSpace = requireFreeSpace
        self.removeItem = removeItem
        self.runProcessToFile = runProcessToFile
        self.moveItem = moveItem
        self.runRequired = runRequired
        self.log = log
    }
}

public struct RuntimeInstallVMDiskProvisioner {
    public let context: RuntimeInstallVMDiskProvisioningContext
    public let operations: RuntimeInstallVMDiskProvisioningOperations

    public init(
        context: RuntimeInstallVMDiskProvisioningContext,
        operations: RuntimeInstallVMDiskProvisioningOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func provision(diskGiB: Int) throws {
        if !operations.fileExists(context.vmDisk), operations.fileExists(context.rootfsBase) {
            try createDiskFromRootfs()
        }
        guard operations.fileExists(context.vmDisk) else {
            throw RuntimeWorkflowError.operationFailed("missing file: \(context.rootfsBase.path)")
        }
        try operations.runRequired(context.truncateExecutable, ["-s", "\(diskGiB)G", context.vmDisk.path])
    }

    private func createDiskFromRootfs() throws {
        try operations.requireFreeSpace(
            context.vmDisk.deletingLastPathComponent(),
            (try operations.fileSize(context.rootfsBase) * 6) + context.freeSpaceMarginBytes,
            "provision-vm-disk"
        )
        let temporary = context.vmDisk
            .deletingLastPathComponent()
            .appendingPathComponent(".\(context.vmDisk.lastPathComponent).tmp")
        if operations.fileExists(temporary) {
            try operations.removeItem(temporary)
        }
        try operations.runProcessToFile(
            context.gunzipExecutable,
            ["-c", context.rootfsBase.path],
            temporary
        )
        try operations.moveItem(temporary, context.vmDisk)
        operations.log("created vm disk path=\(context.vmDisk.path) source=\(context.rootfsBase.lastPathComponent)")
    }
}
