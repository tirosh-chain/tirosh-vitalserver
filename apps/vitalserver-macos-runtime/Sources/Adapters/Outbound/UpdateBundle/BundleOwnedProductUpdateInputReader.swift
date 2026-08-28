import Contracts
import CryptoKit
import Foundation

public enum BundleOwnedProductUpdateInputReadError: Error, Equatable {
    case invalidInvocationPath(path: String)
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

public struct VerifiedBundleOwnedProductUpdateInput:
    Equatable, Sendable
{
    public let invocation: UpdateBootstrapHandoffInvocation
    public let specification: ProductUpdateSpecification
    public let stagedBundleRoot: URL

    public init(
        invocation: UpdateBootstrapHandoffInvocation,
        specification: ProductUpdateSpecification,
        stagedBundleRoot: URL
    ) {
        self.invocation = invocation
        self.specification = specification
        self.stagedBundleRoot = stagedBundleRoot
    }
}

public struct BundleOwnedProductUpdateInputReadOperations {
    public let pathState: (URL) -> RuntimePathState
    public let fileSize: (URL) throws -> UInt64
    public let readData: (URL) throws -> Data

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        fileSize: @escaping (URL) throws -> UInt64,
        readData: @escaping (URL) throws -> Data
    ) {
        self.pathState = pathState
        self.fileSize = fileSize
        self.readData = readData
    }
}

public struct BundleOwnedProductUpdateInputReader {
    public static let maximumDocumentBytes: UInt64 = 1_048_576
    public let operations: BundleOwnedProductUpdateInputReadOperations

    public init(operations: BundleOwnedProductUpdateInputReadOperations) {
        self.operations = operations
    }

    public func read(
        invocationURL: URL
    ) throws -> VerifiedBundleOwnedProductUpdateInput {
        let invocationURL = invocationURL.standardizedFileURL
        guard invocationURL.lastPathComponent == "invocation.json",
              invocationURL.deletingLastPathComponent().lastPathComponent
                == "handoff" else {
            throw BundleOwnedProductUpdateInputReadError
                .invalidInvocationPath(path: invocationURL.path)
        }
        let stagedBundleRoot = invocationURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        let invocation: UpdateBootstrapHandoffInvocation = try decode(
            at: invocationURL
        )
        let specificationURL = try resolve(
            invocation.specificationRelativePath,
            below: stagedBundleRoot
        )
        let specificationData = try readFile(at: specificationURL)
        let actualDigest = sha256(specificationData)
        guard actualDigest == invocation.updateSpecificationSHA256 else {
            throw BundleOwnedProductUpdateInputReadError.digestMismatch(
                path: specificationURL.path,
                expected: invocation.updateSpecificationSHA256,
                actual: actualDigest
            )
        }
        let specification: ProductUpdateSpecification
        do {
            specification = try JSONDecoder().decode(
                ProductUpdateSpecification.self,
                from: specificationData
            )
        } catch {
            throw BundleOwnedProductUpdateInputReadError.decodeFailed(
                path: specificationURL.path,
                reason: String(describing: error)
            )
        }
        return VerifiedBundleOwnedProductUpdateInput(
            invocation: invocation,
            specification: specification,
            stagedBundleRoot: stagedBundleRoot
        )
    }

    private func decode<Value: Decodable>(at url: URL) throws -> Value {
        let data = try readFile(at: url)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw BundleOwnedProductUpdateInputReadError.decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func readFile(at url: URL) throws -> Data {
        switch operations.pathState(url) {
        case .file:
            break
        case .missing:
            throw BundleOwnedProductUpdateInputReadError.missing(
                path: url.path
            )
        case .directory:
            throw unexpected(url, state: "directory")
        case .other(let value), .unknown(let value):
            throw unexpected(url, state: value)
        case .inspectFailed(let reason):
            throw BundleOwnedProductUpdateInputReadError.inspectionFailed(
                path: url.path,
                reason: reason
            )
        }
        do {
            let size = try operations.fileSize(url)
            guard size <= Self.maximumDocumentBytes else {
                throw BundleOwnedProductUpdateInputReadError.documentTooLarge(
                    path: url.path,
                    maximumBytes: Self.maximumDocumentBytes,
                    actualBytes: size
                )
            }
            let data = try operations.readData(url)
            guard UInt64(data.count) <= Self.maximumDocumentBytes else {
                throw BundleOwnedProductUpdateInputReadError.documentTooLarge(
                    path: url.path,
                    maximumBytes: Self.maximumDocumentBytes,
                    actualBytes: UInt64(data.count)
                )
            }
            return data
        } catch let error as BundleOwnedProductUpdateInputReadError {
            throw error
        } catch {
            throw BundleOwnedProductUpdateInputReadError.readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func resolve(_ relativePath: String, below root: URL) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard !relativePath.hasPrefix("/"), url.path.hasPrefix(prefix) else {
            throw BundleOwnedProductUpdateInputReadError
                .pathEscapesStagedBundle(relativePath: relativePath)
        }
        return url
    }

    private func unexpected(
        _ url: URL,
        state: String
    ) -> BundleOwnedProductUpdateInputReadError {
        .unexpectedPathState(path: url.path, state: state)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
