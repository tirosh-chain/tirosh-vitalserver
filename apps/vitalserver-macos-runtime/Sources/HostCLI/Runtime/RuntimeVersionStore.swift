import Foundation
import Contracts

struct RuntimeVersionStore {
    static let missingVersionValue = "missing-version"
    static let invalidVersionValue = "invalid-version"

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

    func readVersion() -> RuntimeVersionReadResult {
        guard fileExists(versionFile) else {
            return .missing
        }
        do {
            let data = try readData(versionFile)
            guard
                let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let version = document["runtimeVersion"] as? String,
                !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .failed("runtime-version.json is missing runtimeVersion")
            }
            return .loaded(version)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func readVersionValue() -> String {
        switch readVersion() {
        case .missing:
            return Self.missingVersionValue
        case .loaded(let version):
            return version
        case .failed:
            return Self.invalidVersionValue
        }
    }

    private func writeDocument(_ document: some Encodable) throws {
        let data = try JSONEncoder.pretty.encode(document)
        try createDirectory(versionFile.deletingLastPathComponent(), true)
        try writeData(data, versionFile)
    }
}

enum RuntimeVersionReadResult: Equatable {
    case missing
    case loaded(String)
    case failed(String)
}
