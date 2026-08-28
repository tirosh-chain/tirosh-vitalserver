import Contracts
import CryptoKit
import Foundation

public enum HostPlatformLayerEffectConfigurationReadError: Error, Equatable {
    case hostPlatformLayerMissing
    case pathEscapesStagedBundle(relativePath: String)
    case missing(path: String)
    case unexpectedPathState(path: String, state: String)
    case inspectionFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case documentTooLarge(
        path: String,
        maximumBytes: UInt64,
        actualBytes: UInt64
    )
    case decodeFailed(path: String, reason: String)
    case digestMismatch(path: String, expected: String, actual: String)
}

public struct HostPlatformUpdateProofDocuments: Equatable, Sendable {
    public let layerPlan: ProductUpdateLayerPlan
    public let configuration: HostPlatformLayerEffectConfiguration

    public init(
        layerPlan: ProductUpdateLayerPlan,
        configuration: HostPlatformLayerEffectConfiguration
    ) {
        self.layerPlan = layerPlan
        self.configuration = configuration
    }
}

public struct HostPlatformLayerEffectConfigurationReader {
    public static let maximumDocumentBytes: UInt64 = 1_048_576
    public let operations: BundleOwnedProductUpdateInputReadOperations

    public init(operations: BundleOwnedProductUpdateInputReadOperations) {
        self.operations = operations
    }

    public func read(
        specification: ProductUpdateSpecification,
        stagedBundleRoot: URL
    ) throws -> HostPlatformUpdateProofDocuments {
        let layers = specification.layerPlan.filter { $0.layer == .hostPlatform }
        guard layers.count == 1, let layerPlan = layers.first else {
            throw HostPlatformLayerEffectConfigurationReadError
                .hostPlatformLayerMissing
        }
        let configurationURL = try resolve(
            layerPlan.effectExecutor.configurationArtifact.relativePath,
            below: stagedBundleRoot
        )
        let data = try readFile(at: configurationURL)
        let actualDigest = sha256(data)
        let expectedDigest = layerPlan.effectExecutor.configurationArtifact.sha256
        guard actualDigest == expectedDigest else {
            throw HostPlatformLayerEffectConfigurationReadError.digestMismatch(
                path: configurationURL.path,
                expected: expectedDigest,
                actual: actualDigest
            )
        }
        let configuration: HostPlatformLayerEffectConfiguration
        do {
            configuration = try JSONDecoder().decode(
                HostPlatformLayerEffectConfiguration.self,
                from: data
            )
        } catch {
            throw HostPlatformLayerEffectConfigurationReadError.decodeFailed(
                path: configurationURL.path,
                reason: String(describing: error)
            )
        }
        return HostPlatformUpdateProofDocuments(
            layerPlan: layerPlan,
            configuration: configuration
        )
    }

    private func readFile(at url: URL) throws -> Data {
        switch operations.pathState(url) {
        case .file:
            break
        case .missing:
            throw HostPlatformLayerEffectConfigurationReadError.missing(
                path: url.path
            )
        case .directory:
            throw unexpected(url, state: "directory")
        case .other(let value), .unknown(let value):
            throw unexpected(url, state: value)
        case .inspectFailed(let reason):
            throw HostPlatformLayerEffectConfigurationReadError
                .inspectionFailed(
                    path: url.path,
                    reason: reason
                )
        }
        do {
            let size = try operations.fileSize(url)
            guard size <= Self.maximumDocumentBytes else {
                throw HostPlatformLayerEffectConfigurationReadError
                    .documentTooLarge(
                        path: url.path,
                        maximumBytes: Self.maximumDocumentBytes,
                        actualBytes: size
                    )
            }
            let data = try operations.readData(url)
            guard UInt64(data.count) <= Self.maximumDocumentBytes else {
                throw HostPlatformLayerEffectConfigurationReadError
                    .documentTooLarge(
                        path: url.path,
                        maximumBytes: Self.maximumDocumentBytes,
                        actualBytes: UInt64(data.count)
                    )
            }
            return data
        } catch let error as HostPlatformLayerEffectConfigurationReadError {
            throw error
        } catch {
            throw HostPlatformLayerEffectConfigurationReadError.readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func resolve(_ relativePath: String, below root: URL) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard !relativePath.hasPrefix("/"), url.path.hasPrefix(prefix) else {
            throw HostPlatformLayerEffectConfigurationReadError
                .pathEscapesStagedBundle(relativePath: relativePath)
        }
        return url
    }

    private func unexpected(
        _ url: URL,
        state: String
    ) -> HostPlatformLayerEffectConfigurationReadError {
        .unexpectedPathState(path: url.path, state: state)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
