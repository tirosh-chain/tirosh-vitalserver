import Contracts
import Foundation

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

public extension RuntimeManagedBackupArtifact {
    func source(in paths: RuntimeBackupStorePaths) -> URL {
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

    func backupPath(in backup: URL) -> URL {
        backup.appendingPathComponent(backupDirectoryName)
    }

    func restoreDestination(
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
