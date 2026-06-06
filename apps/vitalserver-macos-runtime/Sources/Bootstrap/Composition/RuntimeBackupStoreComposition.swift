import Application
import Foundation
import Infrastructure

public struct RuntimeBackupStoreCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(installedPaths: InstalledRuntimePaths) {
        self.installedPaths = installedPaths
    }
}

public struct RuntimeBackupStoreCompositionOperations {
    let fileStore: RuntimeFileStore
    let timestamp: () -> String
    let isoTimestamp: () -> String
    let runRequired: (String, [String]) throws -> Void
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        timestamp: @escaping () -> String,
        isoTimestamp: @escaping () -> String,
        runRequired: @escaping (String, [String]) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.timestamp = timestamp
        self.isoTimestamp = isoTimestamp
        self.runRequired = runRequired
        self.log = log
    }
}

public enum RuntimeBackupStoreComposition {
    public static func make(
        context: RuntimeBackupStoreCompositionContext,
        operations: RuntimeBackupStoreCompositionOperations
    ) -> RuntimeBackupStore {
        RuntimeBackupStore(
            paths: RuntimeBackupStorePaths(
                backupsDirectory: context.installedPaths.backupsDirectory,
                rootfsBase: context.installedPaths.runtimeDirectory
                    .appendingPathComponent(Constants.Artifacts.rootfsBase),
                runtimeVersion: context.installedPaths.runtimeDirectory
                    .appendingPathComponent(Constants.Artifacts.runtimeVersion),
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: context.installedPaths.nginxDirectory,
                guestDeploy: context.installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            metadata: RuntimeBackupStoreMetadata(
                productIdentifier: Constants.Product.identifier,
                rootfsBaseName: Constants.Artifacts.rootfsBase,
                runtimeVersionName: Constants.Artifacts.runtimeVersion,
                backupManifestName: Constants.Artifacts.backupManifest,
                vmDiskName: Constants.BootAssets.disk,
                runtimeToolPaths: [
                    URL(fileURLWithPath: Constants.InstallPaths.vmBin),
                    URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
                    URL(fileURLWithPath: Constants.InstallPaths.uninstall),
                ]
            ),
            timestamp: operations.timestamp,
            isoTimestamp: operations.isoTimestamp,
            fileExists: operations.fileStore.fileExists,
            directoryExists: operations.fileStore.directoryExists,
            createDirectory: { url, withIntermediateDirectories in
                try operations.fileStore.createDirectory(
                    at: url,
                    withIntermediateDirectories: withIntermediateDirectories
                )
            },
            copyItem: { source, destination in
                try operations.fileStore.copyItem(at: source, to: destination)
            },
            removeItem: { url in
                try operations.fileStore.removeItem(at: url)
            },
            writeData: { data, url in
                try operations.fileStore.writeData(data, to: url, options: [])
            },
            contentsOfDirectory: { url in
                try operations.fileStore.contentsOfDirectory(at: url, skipsHiddenFiles: false)
            },
            childDirectories: { url, fragment in
                try operations.fileStore.childDirectories(
                    at: url,
                    nameContains: fragment,
                    skipsHiddenFiles: true
                )
            },
            chmodExecutable: { url in
                try operations.runRequired(Constants.Commands.chmod, ["0755", url.path])
            },
            log: operations.log
        )
    }
}
