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
    public var versionFile: URL
    public var metadata: RuntimeVersionStoreMetadata
    public var timestamp: () -> String
    public var versionPathState: (URL) -> RuntimePathState
    public var createDirectory: (URL, Bool) throws -> Void
    public var readData: (URL) throws -> Data
    public var writeData: (Data, URL) throws -> Void

    public init(
        versionFile: URL,
        metadata: RuntimeVersionStoreMetadata,
        timestamp: @escaping () -> String,
        versionPathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.versionFile = versionFile
        self.metadata = metadata
        self.timestamp = timestamp
        self.versionPathState = versionPathState
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
        let state = versionPathState(versionFile)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .directory, .other:
            return .failed(
                RuntimeVersionStoreError.unexpectedVersionPathState(
                    path: versionFile.path,
                    state: state.rawValue
                ).description
            )
        case .inspectFailed(let reason):
            return .failed(
                RuntimeVersionStoreError.versionPathInspectionFailed(
                    path: versionFile.path,
                    reason: reason
                ).description
            )
        case .unknown(let value):
            return .failed(
                RuntimeVersionStoreError.unexpectedVersionPathState(
                    path: versionFile.path,
                    state: value
                ).description
            )
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
