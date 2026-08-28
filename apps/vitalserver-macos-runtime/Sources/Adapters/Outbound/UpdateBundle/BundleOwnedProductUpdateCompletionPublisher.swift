import Contracts
import CryptoKit
import Foundation

public enum BundleOwnedProductUpdateCompletionPublishError:
    Error, Equatable
{
    case pathEscapesStagedBundle(relativePath: String)
    case destinationAlreadyExists(path: String, state: String)
    case destinationInspectionFailed(path: String, reason: String)
    case encodeFailed(document: String, reason: String)
    case writeFailed(path: String, reason: String)
}

public struct PublishedBundleOwnedProductUpdateCompletion:
    Equatable, Sendable
{
    public let reportURL: URL
    public let reportSHA256: String
    public let receiptURL: URL

    public init(
        reportURL: URL,
        reportSHA256: String,
        receiptURL: URL
    ) {
        self.reportURL = reportURL
        self.reportSHA256 = reportSHA256
        self.receiptURL = receiptURL
    }
}

public struct BundleOwnedProductUpdateCompletionPublishOperations {
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void
    ) {
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.writeData = writeData
    }
}

public struct BundleOwnedProductUpdateCompletionPublisher {
    public static let reportRelativePath =
        "handoff/product-update-execution-report.json"

    public let stagedBundleRoot: URL
    public let operations:
        BundleOwnedProductUpdateCompletionPublishOperations

    public init(
        stagedBundleRoot: URL,
        operations: BundleOwnedProductUpdateCompletionPublishOperations
    ) {
        self.stagedBundleRoot = stagedBundleRoot.standardizedFileURL
        self.operations = operations
    }

    public func publish(
        report: ProductUpdateExecutionReport,
        invocation: UpdateBootstrapHandoffInvocation
    ) throws -> PublishedBundleOwnedProductUpdateCompletion {
        let reportURL = try resolve(Self.reportRelativePath)
        let receiptURL = try resolve(
            invocation.completionReceiptRelativePath
        )
        try requireMissing(reportURL)
        try requireMissing(receiptURL)

        let reportData = try encode(report, document: "execution report")
        let reportSHA256 = sha256(reportData)
        let receipt = UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: invocation.updateId,
            requestId: invocation.requestId,
            bootstrapEnvelopeId: invocation.bootstrapEnvelopeId,
            updateSpecificationSHA256:
                invocation.updateSpecificationSHA256,
            expectedJournalRevision: invocation.expectedJournalRevision,
            outcome: report.state == .succeeded ? .succeeded : .failed,
            reportRelativePath: Self.reportRelativePath,
            reportSHA256: reportSHA256,
            failureReason: report.failure?.message,
            finishedAt: report.finishedAt
        )
        let receiptData = try encode(
            receipt,
            document: "completion receipt"
        )

        try write(reportData, to: reportURL)
        try write(receiptData, to: receiptURL)
        return PublishedBundleOwnedProductUpdateCompletion(
            reportURL: reportURL,
            reportSHA256: reportSHA256,
            receiptURL: receiptURL
        )
    }

    private func encode<Value: Encodable>(
        _ value: Value,
        document: String
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(value)
        } catch {
            throw BundleOwnedProductUpdateCompletionPublishError.encodeFailed(
                document: document,
                reason: String(describing: error)
            )
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try operations.createDirectory(
                url.deletingLastPathComponent(),
                true
            )
            try operations.writeData(data, url, [.atomic])
        } catch {
            throw BundleOwnedProductUpdateCompletionPublishError.writeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func resolve(_ relativePath: String) throws -> URL {
        let url = stagedBundleRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let prefix = stagedBundleRoot.path.hasSuffix("/")
            ? stagedBundleRoot.path
            : stagedBundleRoot.path + "/"
        guard !relativePath.hasPrefix("/"), url.path.hasPrefix(prefix) else {
            throw BundleOwnedProductUpdateCompletionPublishError
                .pathEscapesStagedBundle(relativePath: relativePath)
        }
        return url
    }

    private func requireMissing(_ url: URL) throws {
        switch operations.pathState(url) {
        case .missing:
            return
        case .file:
            throw existing(url, state: "file")
        case .directory:
            throw existing(url, state: "directory")
        case .other(let state), .unknown(let state):
            throw existing(url, state: state)
        case .inspectFailed(let reason):
            throw BundleOwnedProductUpdateCompletionPublishError
                .destinationInspectionFailed(path: url.path, reason: reason)
        }
    }

    private func existing(
        _ url: URL,
        state: String
    ) -> BundleOwnedProductUpdateCompletionPublishError {
        .destinationAlreadyExists(path: url.path, state: state)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
