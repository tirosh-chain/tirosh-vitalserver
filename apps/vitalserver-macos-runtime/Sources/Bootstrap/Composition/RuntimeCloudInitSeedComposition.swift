import Application
import Foundation
import HostAdapters

public enum RuntimeCloudInitSeedComposition {
    public static func make(
        runtimeDirectory: URL,
        fileStore: RuntimeFileStore,
        runRequired: @escaping (String, [String]) throws -> Void,
        instanceID: @escaping () -> String = defaultInstanceID
    ) -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedWriter(
            context: context(runtimeDirectory: runtimeDirectory),
            operations: operations(
                fileStore: fileStore,
                runRequired: runRequired,
                instanceID: instanceID
            )
        )
    }

    public static func context(runtimeDirectory: URL) -> RuntimeCloudInitSeedContext {
        RuntimeCloudInitSeedContext(
            runtimeDirectory: runtimeDirectory,
            seedImageName: Constants.BootAssets.cloudInit,
            seedVolumeName: "cidata",
            hdiutilExecutable: Constants.Commands.hdiutil
        )
    }

    public static func operations(
        fileStore: RuntimeFileStore,
        runRequired: @escaping (String, [String]) throws -> Void,
        instanceID: @escaping () -> String = defaultInstanceID
    ) -> RuntimeCloudInitSeedOperations {
        RuntimeCloudInitSeedOperations(
            directoryExists: { url in
                fileStore.directoryExists(url)
            },
            fileExists: { url in
                fileStore.fileExists(url)
            },
            removeItem: { url in
                try fileStore.removeItem(at: url)
            },
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            writeData: { data, url, options in
                try fileStore.writeData(data, to: url, options: options)
            },
            runRequired: runRequired,
            instanceID: instanceID
        )
    }

    public static func defaultInstanceID() -> String {
        "tirosh-\(UUID().uuidString.lowercased())"
    }
}
