import Application
import Bootstrap
import Foundation
import OutboundAdapters

public enum RuntimeCloudInitSeedComposition {
    public static func make(
        runtimeDirectory: URL,
        fileStore: RuntimeFileStore,
        buildSeedImage: @escaping (RuntimeCloudInitSeedImageBuildRequest) throws -> Void,
        instanceID: @escaping () -> String = defaultInstanceID
    ) -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedWriter(
            context: context(runtimeDirectory: runtimeDirectory),
            operations: operations(
                fileStore: fileStore,
                buildSeedImage: buildSeedImage,
                instanceID: instanceID
            )
        )
    }

    public static func context(runtimeDirectory: URL) -> RuntimeCloudInitSeedContext {
        RuntimeCloudInitSeedContext(
            runtimeDirectory: runtimeDirectory,
            seedImageName: Constants.BootAssets.cloudInit,
            seedVolumeName: "cidata"
        )
    }

    public static func operations(
        fileStore: RuntimeFileStore,
        buildSeedImage: @escaping (RuntimeCloudInitSeedImageBuildRequest) throws -> Void,
        instanceID: @escaping () -> String = defaultInstanceID
    ) -> RuntimeCloudInitSeedOperations {
        RuntimeCloudInitSeedOperations(
            pathState: { url in
                fileStore.pathState(at: url)
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
            buildSeedImage: buildSeedImage,
            instanceID: instanceID
        )
    }

    public static func defaultInstanceID() -> String {
        "tirosh-\(UUID().uuidString.lowercased())"
    }
}
