import Foundation
import Contracts
import Errors

public struct RuntimeInstallVMDiskProvisioningContext {
    public let rootfsBase: URL
    public let vmDisk: URL
    public let runtimeDataDisk: URL
    public let gunzipExecutable: String
    public let truncateExecutable: String
    public let freeSpaceMarginBytes: UInt64

    public init(
        rootfsBase: URL,
        vmDisk: URL,
        runtimeDataDisk: URL,
        gunzipExecutable: String,
        truncateExecutable: String,
        freeSpaceMarginBytes: UInt64
    ) {
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.runtimeDataDisk = runtimeDataDisk
        self.gunzipExecutable = gunzipExecutable
        self.truncateExecutable = truncateExecutable
        self.freeSpaceMarginBytes = freeSpaceMarginBytes
    }
}

public struct RuntimeInstallVMDiskProvisioningOperations {
    public let fileState: (URL) -> RuntimeFileState
    public let fileSize: (URL) throws -> UInt64
    public let requireFreeSpace: (URL, UInt64, String) throws -> Void
    public let removeItem: (URL) throws -> Void
    public let runProcessToFile: (String, [String], URL) throws -> Void
    public let moveItem: (URL, URL) throws -> Void
    public let runRequired: (String, [String]) throws -> Void
    public let log: (String) -> Void

    public init(
        fileState: @escaping (URL) -> RuntimeFileState,
        fileSize: @escaping (URL) throws -> UInt64,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        runRequired: @escaping (String, [String]) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileState = fileState
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

    public func provision(
        diskGiB: Int,
        runtimeDataDiskGiB: Int = 16
    ) throws {
        let vmDiskState = try stateForExistingOrMissingFile(context.vmDisk)
        if vmDiskState == .missing {
            try requireExistingFile(context.rootfsBase)
        }
        let runtimeDataDiskState = try stateForExistingOrMissingFile(context.runtimeDataDisk)
        try requireProvisioningFreeSpace(
            vmDiskState: vmDiskState,
            runtimeDataDiskState: runtimeDataDiskState,
            runtimeDataDiskGiB: runtimeDataDiskGiB
        )
        if vmDiskState == .missing {
            try createDiskFromRootfs()
            try requireExistingFile(context.vmDisk)
            try operations.runRequired(context.truncateExecutable, ["-s", "\(diskGiB)G", context.vmDisk.path])
        } else {
            operations.log("preserved vm disk path=\(context.vmDisk.path)")
        }
        try provisionRuntimeDataDisk(
            context.runtimeDataDisk,
            state: runtimeDataDiskState,
            diskGiB: runtimeDataDiskGiB
        )
    }

    private func createDiskFromRootfs() throws {
        let temporary = context.vmDisk
            .deletingLastPathComponent()
            .appendingPathComponent(".\(context.vmDisk.lastPathComponent).tmp")
        let temporaryState = try stateForExistingOrMissingFile(temporary)
        if temporaryState == .present || temporaryState == .executable {
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

    private func requireProvisioningFreeSpace(
        vmDiskState: RuntimeFileState,
        runtimeDataDiskState: RuntimeFileState,
        runtimeDataDiskGiB: Int
    ) throws {
        let requiresVMDisk = vmDiskState == .missing
        let requiresRuntimeDataDisk = runtimeDataDiskState == .missing

        switch (requiresVMDisk, requiresRuntimeDataDisk) {
        case (false, false):
            return
        case (true, false):
            try operations.requireFreeSpace(
                context.vmDisk.deletingLastPathComponent(),
                try requiredVMDiskFreeSpaceBytes(),
                "provision-vm-disk"
            )
        case (false, true):
            try operations.requireFreeSpace(
                context.runtimeDataDisk.deletingLastPathComponent(),
                requiredRuntimeDataDiskFreeSpaceBytes(diskGiB: runtimeDataDiskGiB),
                "provision-runtime-data-disk"
            )
        case (true, true):
            try operations.requireFreeSpace(
                context.vmDisk.deletingLastPathComponent(),
                try requiredVMDiskFreeSpaceBytes()
                    + requiredRuntimeDataDiskFreeSpaceBytes(diskGiB: runtimeDataDiskGiB),
                "provision-vm-and-runtime-data-disks"
            )
        }
    }

    private func requiredVMDiskFreeSpaceBytes() throws -> UInt64 {
        (try operations.fileSize(context.rootfsBase) * 6) + context.freeSpaceMarginBytes
    }

    private func requiredRuntimeDataDiskFreeSpaceBytes(diskGiB: Int) -> UInt64 {
        UInt64(diskGiB) * 1024 * 1024 * 1024 + context.freeSpaceMarginBytes
    }

    private func provisionRuntimeDataDisk(
        _ disk: URL,
        state: RuntimeFileState,
        diskGiB: Int
    ) throws {
        switch state {
        case .present, .executable:
            try validateExistingRuntimeDataDisk(disk, diskGiB: diskGiB)
            operations.log("preserved runtime data disk path=\(disk.path)")
        case .missing:
            try operations.runRequired(context.truncateExecutable, ["-s", "\(diskGiB)G", disk.path])
            operations.log("created runtime data disk path=\(disk.path) size=\(diskGiB)G")
        case .inspectFailed, .unknown:
            // Covered by stateForExistingOrMissingFile before this switch.
            break
        }
    }

    private func validateExistingRuntimeDataDisk(_ disk: URL, diskGiB: Int) throws {
        let requiredBytes = UInt64(diskGiB) * 1024 * 1024 * 1024
        let actualBytes = try operations.fileSize(disk)
        guard actualBytes >= requiredBytes else {
            throw RuntimeInstallVMDiskProvisioningError.runtimeDataDiskTooSmall(
                path: disk.path,
                actualBytes: actualBytes,
                requiredBytes: requiredBytes
            )
        }
    }

    private func requireExistingFile(_ url: URL) throws {
        let state = try stateForExistingOrMissingFile(url)
        if state == .present || state == .executable {
            return
        }
        throw RuntimeInstallVMDiskProvisioningError.missingFile(url.path)
    }

    private func stateForExistingOrMissingFile(_ url: URL) throws -> RuntimeFileState {
        let state = operations.fileState(url)
        switch state {
        case .present, .executable, .missing:
            return state
        case .inspectFailed(let reason):
            throw RuntimeInstallVMDiskProvisioningError.fileInspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            throw RuntimeInstallVMDiskProvisioningError.unexpectedFileState(path: url.path, state: value)
        }
    }
}
