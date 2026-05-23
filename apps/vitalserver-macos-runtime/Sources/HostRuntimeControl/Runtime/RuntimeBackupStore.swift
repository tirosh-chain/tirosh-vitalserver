import Foundation
import RuntimeCore
import RuntimeContracts

struct RuntimeBackupStorePaths {
    var backupsDirectory: URL
    var rootfsBase: URL
    var runtimeVersion: URL
    var managerApp: URL
    var nginxBundle: URL
    var guestDeploy: URL
    var runtimeTools: URL
}

enum RuntimeManagedBackupArtifact: CaseIterable {
    case appBundle
    case nginxBundle
    case guestDeploy
    case runtimeTools

    static let directoryArtifacts: [RuntimeManagedBackupArtifact] = [
        .appBundle,
        .nginxBundle,
        .guestDeploy,
    ]

    var updateArtifactType: UpdateBundleArtifactType {
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
        backup.appendingPathComponent(updateArtifactType.rawValue)
    }

    func restoreDestination(
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) -> URL {
        switch self {
        case .appBundle:
            return managerAppPath
        case .nginxBundle:
            return nginxDirectory
        case .guestDeploy:
            return deployDirectory
        case .runtimeTools:
            return URL(fileURLWithPath: Constants.InstallPaths.vmBin).deletingLastPathComponent()
        }
    }
}

struct RuntimeBackupStore {
    var paths: RuntimeBackupStorePaths
    var timestamp: () -> String
    var isoTimestamp: () -> String
    var fileExists: (URL) -> Bool
    var directoryExists: (URL) -> Bool
    var createDirectory: (URL, Bool) throws -> Void
    var copyItem: (URL, URL) throws -> Void
    var removeItem: (URL) throws -> Void
    var writeData: (Data, URL) throws -> Void
    var contentsOfDirectory: (URL) throws -> [URL]
    var childDirectories: (URL, String) throws -> [URL]
    var chmodExecutable: (URL) throws -> Void
    var log: (String) -> Void

    func createBackup(reason: String) throws -> URL {
        let backup = paths.backupsDirectory.appendingPathComponent("\(timestamp())-\(reason)")
        try createDirectory(backup, true)

        if fileExists(paths.rootfsBase) {
            log("backup rootfs-base source=\(paths.rootfsBase.path)")
            try copyItem(paths.rootfsBase, backup.appendingPathComponent(Constants.Artifacts.rootfsBase))
        }
        if fileExists(paths.runtimeVersion) {
            log("backup runtime-version source=\(paths.runtimeVersion.path)")
            try copyItem(paths.runtimeVersion, backup.appendingPathComponent(Constants.Artifacts.runtimeVersion))
        }

        for artifact in RuntimeManagedBackupArtifact.directoryArtifacts {
            try backupPathIfExists(artifact.source(in: paths), to: artifact.backupPath(in: backup))
        }
        try backupRuntimeTools(to: RuntimeManagedBackupArtifact.runtimeTools.backupPath(in: backup))

        let manifest = BackupManifest(
            product: Constants.Product.identifier,
            createdAt: isoTimestamp(),
            reason: reason,
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk,
            vmDiskPreserved: true
        )
        try writeData(
            try JSONEncoder.pretty.encode(manifest),
            backup.appendingPathComponent(Constants.Artifacts.backupManifest)
        )
        return backup
    }

    func restoreBackupPathIfExists(_ source: URL, to destination: URL) throws {
        guard fileExists(source) || directoryExists(source) else {
            return
        }
        if fileExists(destination) || directoryExists(destination) {
            try removeItem(destination)
        }
        try copyItem(source, destination)
    }

    func restoreRuntimeToolsIfExists(_ source: URL) throws {
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

    func latestBackup() -> URL? {
        guard let directories = try? childDirectories(paths.backupsDirectory, "-before-") else {
            return nil
        }
        return directories
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
    }

    func requireLatestBackup() throws -> URL {
        guard let backup = latestBackup() else {
            throw LauncherError.missingArgument("no backups available")
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
        for path in [
            Constants.InstallPaths.vmBin,
            Constants.InstallPaths.proxyRun,
            Constants.InstallPaths.uninstall,
        ] {
            let source = URL(fileURLWithPath: path)
            if fileExists(source) {
                try copyItem(source, destination.appendingPathComponent(source.lastPathComponent))
            }
        }
    }
}
