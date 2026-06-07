import Contracts
import Foundation
import Errors

public struct RuntimeBackupStorePaths {
    public var backupsDirectory: URL
    public var rootfsBase: URL
    public var runtimeVersion: URL
    public var managerApp: URL
    public var nginxBundle: URL
    public var guestDeploy: URL
    public var runtimeTools: URL

    public init(
        backupsDirectory: URL,
        rootfsBase: URL,
        runtimeVersion: URL,
        managerApp: URL,
        nginxBundle: URL,
        guestDeploy: URL,
        runtimeTools: URL
    ) {
        self.backupsDirectory = backupsDirectory
        self.rootfsBase = rootfsBase
        self.runtimeVersion = runtimeVersion
        self.managerApp = managerApp
        self.nginxBundle = nginxBundle
        self.guestDeploy = guestDeploy
        self.runtimeTools = runtimeTools
    }
}

public struct RuntimeBackupStoreMetadata {
    public var productIdentifier: String
    public var rootfsBaseName: String
    public var runtimeVersionName: String
    public var backupManifestName: String
    public var vmDiskName: String
    public var runtimeToolPaths: [URL]

    public init(
        productIdentifier: String,
        rootfsBaseName: String,
        runtimeVersionName: String,
        backupManifestName: String,
        vmDiskName: String,
        runtimeToolPaths: [URL]
    ) {
        self.productIdentifier = productIdentifier
        self.rootfsBaseName = rootfsBaseName
        self.runtimeVersionName = runtimeVersionName
        self.backupManifestName = backupManifestName
        self.vmDiskName = vmDiskName
        self.runtimeToolPaths = runtimeToolPaths
    }
}

public enum RuntimeManagedBackupArtifact: CaseIterable, Sendable {
    case appBundle
    case nginxBundle
    case guestDeploy
    case runtimeTools

    public static let directoryArtifacts: [RuntimeManagedBackupArtifact] = [
        .appBundle,
        .nginxBundle,
        .guestDeploy,
    ]

    public var updateArtifactType: UpdateBundleArtifactType {
        switch self {
        case .appBundle:
            return .appBundle
        case .nginxBundle:
            return .nginxBundle
        case .guestDeploy:
            return .guestDeploy
        case .runtimeTools:
            return .runtimeTools
        }
    }

    public func source(in paths: RuntimeBackupStorePaths) -> URL {
        switch self {
        case .appBundle:
            return paths.managerApp
        case .nginxBundle:
            return paths.nginxBundle
        case .guestDeploy:
            return paths.guestDeploy
        case .runtimeTools:
            return paths.runtimeTools
        }
    }

    public func backupPath(in backup: URL) -> URL {
        backup.appendingPathComponent(updateArtifactType.rawValue)
    }

    public func restoreDestination(
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL,
        runtimeToolsDirectory: URL
    ) -> URL {
        switch self {
        case .appBundle:
            return managerAppPath
        case .nginxBundle:
            return nginxDirectory
        case .guestDeploy:
            return deployDirectory
        case .runtimeTools:
            return runtimeToolsDirectory
        }
    }
}

public struct RuntimeBackupStore {
    public var paths: RuntimeBackupStorePaths
    public var metadata: RuntimeBackupStoreMetadata
    public var timestamp: () -> String
    public var isoTimestamp: () -> String
    public var fileExists: (URL) -> Bool
    public var directoryExists: (URL) -> Bool
    public var createDirectory: (URL, Bool) throws -> Void
    public var copyItem: (URL, URL) throws -> Void
    public var removeItem: (URL) throws -> Void
    public var writeData: (Data, URL) throws -> Void
    public var contentsOfDirectory: (URL) throws -> [URL]
    public var childDirectories: (URL, String) throws -> [URL]
    public var chmodExecutable: (URL) throws -> Void
    public var log: (String) -> Void

    public init(
        paths: RuntimeBackupStorePaths,
        metadata: RuntimeBackupStoreMetadata,
        timestamp: @escaping () -> String,
        isoTimestamp: @escaping () -> String,
        fileExists: @escaping (URL) -> Bool,
        directoryExists: @escaping (URL) -> Bool,
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
        self.fileExists = fileExists
        self.directoryExists = directoryExists
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

        let backsUpRootfsBase = fileExists(paths.rootfsBase)
        if backsUpRootfsBase {
            log("backup rootfs-base source=\(paths.rootfsBase.path)")
            try copyItem(paths.rootfsBase, backup.appendingPathComponent(metadata.rootfsBaseName))
        }
        if fileExists(paths.runtimeVersion) {
            log("backup runtime-version source=\(paths.runtimeVersion.path)")
            try copyItem(paths.runtimeVersion, backup.appendingPathComponent(metadata.runtimeVersionName))
        }

        for artifact in RuntimeManagedBackupArtifact.directoryArtifacts {
            try backupPathIfExists(artifact.source(in: paths), to: artifact.backupPath(in: backup))
        }
        try backupRuntimeTools(to: RuntimeManagedBackupArtifact.runtimeTools.backupPath(in: backup))

        let manifest = BackupManifest(
            product: metadata.productIdentifier,
            createdAt: isoTimestamp(),
            reason: reason,
            rootfsBase: backsUpRootfsBase ? metadata.rootfsBaseName : nil,
            vmDisk: metadata.vmDiskName,
            vmDiskPreserved: true
        )
        try writeData(
            try runtimeBackupDocumentEncoder().encode(manifest),
            backup.appendingPathComponent(metadata.backupManifestName)
        )
        return backup
    }

    public func restoreBackupPathIfExists(_ source: URL, to destination: URL) throws {
        guard fileExists(source) || directoryExists(source) else {
            return
        }
        if fileExists(destination) || directoryExists(destination) {
            try removeItem(destination)
        }
        try copyItem(source, destination)
    }

    public func restoreRuntimeToolsIfExists(_ source: URL) throws {
        guard directoryExists(source) else {
            return
        }
        let tools = try contentsOfDirectory(source)
        for tool in tools {
            let destination = paths.runtimeTools.appendingPathComponent(tool.lastPathComponent)
            if fileExists(destination) {
                try removeItem(destination)
            }
            try copyItem(tool, destination)
            try chmodExecutable(destination)
        }
    }

    public func latestBackup() throws -> URL? {
        guard directoryExists(paths.backupsDirectory) else {
            return nil
        }
        let directories = try childDirectories(paths.backupsDirectory, "-before-")
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

    private func backupPathIfExists(_ source: URL, to destination: URL) throws {
        guard fileExists(source) || directoryExists(source) else {
            return
        }
        try copyItem(source, destination)
    }

    private func backupRuntimeTools(to destination: URL) throws {
        try createDirectory(destination, true)
        for source in metadata.runtimeToolPaths {
            if fileExists(source) {
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
