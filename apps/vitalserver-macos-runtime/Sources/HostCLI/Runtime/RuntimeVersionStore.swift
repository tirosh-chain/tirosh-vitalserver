import Foundation

struct RuntimeVersionStore {
    var versionFile: URL
    var timestamp: () -> String
    var fileExists: (URL) -> Bool
    var createDirectory: (URL, Bool) throws -> Void
    var readData: (URL) throws -> Data
    var writeData: (Data, URL) throws -> Void

    func writeInstalledVersion(version: String) throws {
        let document = InstalledRuntimeVersionDocument(
            product: Constants.Product.identifier,
            runtimeVersion: version,
            installedAt: timestamp(),
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk
        )
        try writeDocument(document)
    }

    func writeAppliedVersion(version: String, bundle: URL) throws {
        let document = RuntimeVersionDocument(
            product: Constants.Product.identifier,
            runtimeVersion: version,
            appliedAt: timestamp(),
            bundle: bundle.lastPathComponent,
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk
        )
        try writeDocument(document)
    }

    func readVersionValue(default defaultValue: String) -> String {
        guard fileExists(versionFile),
              let data = try? readData(versionFile),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = document["runtimeVersion"] as? String
        else {
            return defaultValue
        }
        return version
    }

    private func writeDocument(_ document: some Encodable) throws {
        let data = try JSONEncoder.pretty.encode(document)
        try createDirectory(versionFile.deletingLastPathComponent(), true)
        try writeData(data, versionFile)
    }
}
