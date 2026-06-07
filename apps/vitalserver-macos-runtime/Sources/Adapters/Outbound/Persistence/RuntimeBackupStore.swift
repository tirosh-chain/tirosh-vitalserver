import Contracts
import Foundation
import Errors

public struct RuntimeBackupStore {
    public var paths: RuntimeBackupStorePaths
    public var metadata: RuntimeBackupStoreMetadata
    public var timestamp: () -> String
    public var isoTimestamp: () -> String
    public var pathState: (URL) -> RuntimePathState
    public var createDirectory: (URL, Bool) throws -> Void
    public var copyItem: (URL, URL) throws -> Void
    public var removeItem: (URL) throws -> Void
    public var writeData: (Data, URL) throws -> Void
    public var contentsOfDirectory: (URL) throws -> [URL]
    public var childDirectories: (URL, String) throws -> [URL]
    public var chmodExecutable: (URL) throws -> Void
    public var log: (String) -> Void
    private var pathInspector: RuntimeBackupPathInspector {
        RuntimeBackupPathInspector(pathState: pathState)
    }

    public init(
        paths: RuntimeBackupStorePaths,
        metadata: RuntimeBackupStoreMetadata,
        timestamp: @escaping () -> String,
        isoTimestamp: @escaping () -> String,
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        copyItem: @escaping (URL, URL) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        writeData: @escaping (Data, URL) throws -> Void,
        contentsOfDirectory: @escaping (URL) throws -> [URL],
        childDirectories: @escaping (URL, String) throws -> [URL],
        chmodExecutable: @escaping (URL) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.paths = paths
        self.metadata = metadata
        self.timestamp = timestamp
        self.isoTimestamp = isoTimestamp
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.copyItem = copyItem
        self.removeItem = removeItem
        self.writeData = writeData
        self.contentsOfDirectory = contentsOfDirectory
        self.childDirectories = childDirectories
        self.chmodExecutable = chmodExecutable
        self.log = log
    }

    public func createBackup(reason: String) throws -> URL {
        let backup = paths.backupsDirectory.appendingPathComponent("\(timestamp())-\(reason)")
        try createDirectory(backup, true)

        let backsUpRootfsBase = try backupFileIfPresent(
            paths.rootfsBase,
            to: backup.appendingPathComponent(metadata.rootfsBaseName),
            logMessage: "backup rootfs-base source=\(paths.rootfsBase.path)"
        )
        _ = try backupFileIfPresent(
            paths.runtimeVersion,
            to: backup.appendingPathComponent(metadata.runtimeVersionName),
            logMessage: "backup runtime-version source=\(paths.runtimeVersion.path)"
        )

        for artifact in RuntimeManagedBackupArtifact.directoryArtifacts {
            try backupPathIfPresent(artifact.source(in: paths), to: artifact.backupPath(in: backup))
        }
        try backupRuntimeTools(to: RuntimeManagedBackupArtifact.runtimeTools.backupPath(in: backup))

        let manifest = BackupManifest.managedRuntimeBackup(
            product: metadata.productIdentifier,
            createdAt: isoTimestamp(),
            reason: reason,
            rootfsBaseName: metadata.rootfsBaseName,
            backsUpRootfsBase: backsUpRootfsBase,
            vmDiskName: metadata.vmDiskName
        )
        try writeData(
            try runtimeBackupDocumentEncoder().encode(manifest),
            backup.appendingPathComponent(metadata.backupManifestName)
        )
        return backup
    }

    public func restoreBackupPathIfExists(_ source: URL, to destination: URL) throws {
        guard try pathInspector.pathIsPresent(source) else {
            return
        }
        if try pathInspector.pathIsPresent(destination) {
            try removeItem(destination)
        }
        try copyItem(source, destination)
    }

    public func restoreRuntimeToolsIfExists(_ source: URL) throws {
        guard try pathInspector.directoryIsPresent(source) else {
            return
        }
        let tools = try contentsOfDirectory(source)
        for tool in tools {
            guard try pathInspector.fileIsPresent(tool) else {
                throw RuntimeBackupStoreError.unexpectedPathState(path: tool.path, state: pathState(tool).rawValue)
            }
            let destination = paths.runtimeTools.appendingPathComponent(tool.lastPathComponent)
            if try pathInspector.pathIsPresent(destination) {
                try removeItem(destination)
            }
            try copyItem(tool, destination)
            try chmodExecutable(destination)
        }
    }

    public func latestBackup() throws -> URL? {
        guard try pathInspector.directoryIsPresent(paths.backupsDirectory) else {
            return nil
        }
        let directories = try childDirectories(paths.backupsDirectory, RuntimeManagedBackupPolicy.nameFragment)
        return directories
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
    }

    public func requireLatestBackup() throws -> URL {
        guard let backup = try latestBackup() else {
            throw RuntimeBackupStoreError.noBackupsAvailable
        }
        return backup
    }

    private func backupFileIfPresent(
        _ source: URL,
        to destination: URL,
        logMessage: String
    ) throws -> Bool {
        guard try pathInspector.fileIsPresent(source) else {
            return false
        }
        log(logMessage)
        try copyItem(source, destination)
        return true
    }

    private func backupPathIfPresent(_ source: URL, to destination: URL) throws {
        guard try pathInspector.pathIsPresent(source) else {
            return
        }
        try copyItem(source, destination)
    }

    private func backupRuntimeTools(to destination: URL) throws {
        try createDirectory(destination, true)
        for source in metadata.runtimeToolPaths {
            if try pathInspector.fileIsPresent(source) {
                try copyItem(source, destination.appendingPathComponent(source.lastPathComponent))
            }
        }
    }
}

private func runtimeBackupDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
