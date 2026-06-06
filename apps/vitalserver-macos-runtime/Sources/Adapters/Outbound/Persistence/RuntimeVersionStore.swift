import Contracts
import Foundation
import Errors

public struct RuntimeVersionStoreMetadata: Equatable, Sendable {
    public let productIdentifier: String
    public let rootfsBase: String
    public let vmDisk: String

    public init(
        productIdentifier: String,
        rootfsBase: String,
        vmDisk: String
    ) {
        self.productIdentifier = productIdentifier
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
    }
}

public struct RuntimeVersionStore {
    public static let missingVersionValue = "missing-version"
    public static let invalidVersionValue = "invalid-version"

    public var versionFile: URL
    public var metadata: RuntimeVersionStoreMetadata
    public var timestamp: () -> String
    public var fileExists: (URL) -> Bool
    public var createDirectory: (URL, Bool) throws -> Void
    public var readData: (URL) throws -> Data
    public var writeData: (Data, URL) throws -> Void

    public init(
        versionFile: URL,
        metadata: RuntimeVersionStoreMetadata,
        timestamp: @escaping () -> String,
        fileExists: @escaping (URL) -> Bool,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.versionFile = versionFile
        self.metadata = metadata
        self.timestamp = timestamp
        self.fileExists = fileExists
        self.createDirectory = createDirectory
        self.readData = readData
        self.writeData = writeData
    }

    public func writeInstalledVersion(version: String) throws {
        let document = InstalledRuntimeVersionDocument(
            product: metadata.productIdentifier,
            runtimeVersion: version,
            installedAt: timestamp(),
            rootfsBase: metadata.rootfsBase,
            vmDisk: metadata.vmDisk
        )
        try writeDocument(document)
    }

    public func writeAppliedVersion(version: String, bundle: URL) throws {
        let document = RuntimeVersionDocument(
            product: metadata.productIdentifier,
            runtimeVersion: version,
            appliedAt: timestamp(),
            bundle: bundle.lastPathComponent,
            rootfsBase: metadata.rootfsBase,
            vmDisk: metadata.vmDisk
        )
        try writeDocument(document)
    }

    public func readVersion() -> RuntimeVersionReadResult {
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

    public func readVersionValue() -> String {
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
        let data = try runtimeVersionDocumentEncoder().encode(document)
        try createDirectory(versionFile.deletingLastPathComponent(), true)
        try writeData(data, versionFile)
    }
}

public enum RuntimeVersionReadResult: Equatable, Sendable {
    case missing
    case loaded(String)
    case failed(String)
}

private func runtimeVersionDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
