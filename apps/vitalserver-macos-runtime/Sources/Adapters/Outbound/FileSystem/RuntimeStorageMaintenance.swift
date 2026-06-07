import Application
import Contracts
import Foundation
import Errors

public struct RuntimeStorageMaintenanceConfiguration: Equatable, Sendable {
    public let backupKeepCount: Int
    public let stagedBundleKeepCount: Int

    public init(backupKeepCount: Int, stagedBundleKeepCount: Int) {
        self.backupKeepCount = backupKeepCount
        self.stagedBundleKeepCount = stagedBundleKeepCount
    }
}

public struct RuntimeStorageMaintenance {
    public var fileStore: RuntimeFileStore
    public var configuration: RuntimeStorageMaintenanceConfiguration
    public var log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        configuration: RuntimeStorageMaintenanceConfiguration,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.configuration = configuration
        self.log = log
    }

    public func pruneOldRuntimeArtifacts(
        backupsDirectory: URL,
        bundlesDirectory: URL
    ) throws {
        try pruneOldDirectories(
            in: backupsDirectory,
            keep: configuration.backupKeepCount,
            requiredNameFragment: RuntimeManagedBackupPolicy.nameFragment
        )
        try pruneOldDirectories(
            in: bundlesDirectory,
            keep: configuration.stagedBundleKeepCount,
            requiredNameFragment: "update-bundle-"
        )
    }

    public func requireFreeSpace(at url: URL, minimumBytes: UInt64, operation: String) throws {
        let available = try availableBytes(at: url)
        guard available >= minimumBytes else {
            throw RuntimeStorageMaintenanceError.insufficientFreeSpace(
                operation: operation,
                required: minimumBytes,
                available: available
            )
        }
        log("free-space preflight passed operation=\(operation) required=\(formatBytes(minimumBytes)) available=\(formatBytes(available))")
    }

    public func replaceFile(from source: URL, to destination: URL) throws {
        try fileStore.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp")
        log(
            "file replacement started source=\(source.path) destination=\(destination.path) temporary=\(temporary.path) size=\(formatBytes(try fileStore.fileSize(source)))"
        )
        if try expectedFilePathIsPresent(temporary) {
            try fileStore.removeItem(at: temporary)
        }
        try fileStore.copyItem(at: source, to: temporary)
        if try expectedFilePathIsPresent(destination) {
            try fileStore.removeItem(at: destination)
        }
        try fileStore.moveItem(at: temporary, to: destination)
        log("file replacement completed destination=\(destination.path)")
    }

    private func pruneOldDirectories(in directory: URL, keep: Int, requiredNameFragment: String) throws {
        let directoryState = fileStore.pathState(at: directory)
        switch directoryState {
        case .directory:
            break
        case .missing:
            log("runtime artifact prune skipped directory missing path=\(directory.path) requiredNameFragment=\(requiredNameFragment)")
            return
        case .inspectFailed(let reason):
            throw RuntimeStorageMaintenanceError.pathInspectionFailed(path: directory.path, reason: reason)
        case .file, .other, .unknown:
            throw RuntimeStorageMaintenanceError.unexpectedPathState(path: directory.path, state: directoryState.rawValue)
        }

        let matchingDirectories: [URL]
        do {
            matchingDirectories = try fileStore.childDirectories(
                at: directory,
                nameContains: requiredNameFragment,
                skipsHiddenFiles: true
            )
        } catch {
            throw RuntimeStorageMaintenanceError.directoryListingFailed(
                path: directory.path,
                reason: String(describing: error)
            )
        }
        let directories = matchingDirectories.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in directories.dropLast(keep) {
            try fileStore.removeItem(at: directory)
            log("pruned runtime artifact path=\(directory.path)")
        }
    }

    private func availableBytes(at url: URL) throws -> UInt64 {
        let attributes = try fileStore.fileSystemAttributes(forPath: url.path)
        guard attributes.freeBytes > 0 else {
            throw RuntimeStorageMaintenanceError.freeSpaceUnavailable(path: url.path)
        }
        return attributes.freeBytes
    }

    private func expectedFilePathIsPresent(_ url: URL) throws -> Bool {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw RuntimeStorageMaintenanceError.pathInspectionFailed(path: url.path, reason: reason)
        case .directory, .other, .unknown:
            throw RuntimeStorageMaintenanceError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
