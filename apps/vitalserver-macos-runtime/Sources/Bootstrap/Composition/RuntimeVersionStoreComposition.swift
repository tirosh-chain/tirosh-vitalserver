import Application
import Foundation
import Infrastructure

public struct RuntimeVersionStoreCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(installedPaths: InstalledRuntimePaths) {
        self.installedPaths = installedPaths
    }
}

public struct RuntimeVersionStoreCompositionOperations {
    let fileStore: RuntimeFileStore
    let timestamp: () -> String

    public init(
        fileStore: RuntimeFileStore,
        timestamp: @escaping () -> String
    ) {
        self.fileStore = fileStore
        self.timestamp = timestamp
    }
}

public enum RuntimeVersionStoreComposition {
    public static func make(
        context: RuntimeVersionStoreCompositionContext,
        operations: RuntimeVersionStoreCompositionOperations
    ) -> RuntimeVersionStore {
        RuntimeVersionStore(
            versionFile: context.installedPaths.runtimeDirectory
                .appendingPathComponent(Constants.Artifacts.runtimeVersion),
            metadata: RuntimeVersionStoreMetadata(
                productIdentifier: Constants.Product.identifier,
                rootfsBase: Constants.Artifacts.rootfsBase,
                vmDisk: Constants.BootAssets.disk
            ),
            timestamp: operations.timestamp,
            fileExists: operations.fileStore.fileExists,
            createDirectory: { url, withIntermediateDirectories in
                try operations.fileStore.createDirectory(
                    at: url,
                    withIntermediateDirectories: withIntermediateDirectories
                )
            },
            readData: { url in
                try operations.fileStore.readData(url)
            },
            writeData: { data, url in
                try operations.fileStore.writeData(data, to: url, options: [])
            }
        )
    }
}
