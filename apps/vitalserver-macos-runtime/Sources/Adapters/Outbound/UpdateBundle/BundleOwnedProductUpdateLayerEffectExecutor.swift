import Application
import Contracts
import Foundation

public struct BundleOwnedProductUpdateLayerEffectExecutorOperations {
    public let observe: (
        UpdateBootstrapArtifact
    ) -> UpdateBootstrapArtifactObservation
    public let fileState: (URL) -> RuntimeFileState
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let fileSize: (URL) throws -> UInt64
    public let readData: (URL) throws -> Data
    public let run: (String, [String]) -> RuntimeProcessResult

    public init(
        observe: @escaping (
            UpdateBootstrapArtifact
        ) -> UpdateBootstrapArtifactObservation,
        fileState: @escaping (URL) -> RuntimeFileState,
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        fileSize: @escaping (URL) throws -> UInt64,
        readData: @escaping (URL) throws -> Data,
        run: @escaping (String, [String]) -> RuntimeProcessResult
    ) {
        self.observe = observe
        self.fileState = fileState
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.writeData = writeData
        self.fileSize = fileSize
        self.readData = readData
        self.run = run
    }
}

public struct BundleOwnedProductUpdateLayerEffectExecutor {
    public static let maximumReceiptBytes: UInt64 = 1_048_576
    public let stagedBundleRoot: URL
    public let operations: BundleOwnedProductUpdateLayerEffectExecutorOperations

    public init(
        stagedBundleRoot: URL,
        operations: BundleOwnedProductUpdateLayerEffectExecutorOperations
    ) {
        self.stagedBundleRoot = stagedBundleRoot.standardizedFileURL
        self.operations = operations
    }

    public func execute(
        _ request: ProductUpdateLayerEffectRequest
    ) -> ProductUpdateLayerEffectExecutionResult {
        if let result = verify(request.artifact, role: "effect artifact") {
            return result
        }
        let configuration = request.effectExecutor.configurationArtifact
        if let result = verify(configuration, role: "executor configuration") {
            return result
        }
        let executorArtifact = UpdateBootstrapArtifact(
            id: request.effectExecutor.id,
            relativePath: request.effectExecutor.relativePath,
            sha256: request.effectExecutor.sha256,
            sizeBytes: request.effectExecutor.sizeBytes,
            mediaType: request.effectExecutor.mediaType
        )
        if let result = verify(executorArtifact, role: "effect executor") {
            return result
        }

        let executorURL: URL
        do {
            executorURL = try resolve(request.effectExecutor.relativePath)
        } catch {
            return .failed(reason: String(describing: error))
        }
        switch operations.fileState(executorURL) {
        case .executable:
            break
        case .missing:
            return .unavailable(reason: "effect executor is missing")
        case .present:
            return .unavailable(reason: "effect executor is not executable")
        case .inspectFailed(let reason):
            return .failed(
                reason: "effect executor inspection failed: \(reason)"
            )
        case .unknown(let state):
            return .failed(reason: "effect executor state is unknown: \(state)")
        }

        let paths: (request: URL, receipt: URL)
        do {
            paths = try effectPaths(for: request)
            try requireMissing(paths.request)
            try requireMissing(paths.receipt)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                ProductUpdateLayerEffectInvocation(request: request)
            )
            try operations.createDirectory(
                paths.request.deletingLastPathComponent(),
                true
            )
            try operations.writeData(data, paths.request, [.atomic])
        } catch {
            return .failed(
                reason: "effect invocation publication failed: \(error)"
            )
        }

        let process = operations.run(
            executorURL.path,
            [
                "execute",
                "--request", paths.request.path,
                "--receipt", paths.receipt.path,
            ]
        )
        if let issue = process.executionIssue {
            return .unavailable(
                reason: "effect executor launch failed: \(issue.message)"
            )
        }
        switch readReceipt(at: paths.receipt) {
        case .success(let receipt):
            return .completed(receipt)
        case .failure(let reason):
            if process.exitCode == 0 {
                return .unavailable(
                    reason:
                        "effect receipt unavailable after zero exit: \(reason)"
                )
            }
            return .failed(
                reason:
                    "effect executor exited \(process.exitCode) without a readable receipt: \(reason)"
            )
        }
    }

    private func verify(
        _ artifact: UpdateBootstrapArtifact,
        role: String
    ) -> ProductUpdateLayerEffectExecutionResult? {
        do {
            _ = try resolve(artifact.relativePath)
        } catch {
            return .failed(reason: "\(role) path is invalid: \(error)")
        }
        switch operations.observe(artifact) {
        case .available(let sha256, let sizeBytes):
            guard sha256 == artifact.sha256 else {
                return .failed(
                    reason:
                        "\(role) digest mismatch expected=\(artifact.sha256) actual=\(sha256)"
                )
            }
            guard sizeBytes == artifact.sizeBytes else {
                return .failed(
                    reason:
                        "\(role) size mismatch expected=\(artifact.sizeBytes) actual=\(sizeBytes)"
                )
            }
            return nil
        case .unavailable(let reason):
            return .unavailable(reason: "\(role) unavailable: \(reason)")
        case .failed(let reason):
            return .failed(reason: "\(role) verification failed: \(reason)")
        }
    }

    private func effectPaths(
        for request: ProductUpdateLayerEffectRequest
    ) throws -> (request: URL, receipt: URL) {
        let stem = "\(request.layer.rawValue)-\(request.operation.rawValue)"
        return (
            try resolve("handoff/layer-effects/\(stem)-request.json"),
            try resolve("handoff/layer-effects/\(stem)-receipt.json")
        )
    }

    private func resolve(_ relativePath: String) throws -> URL {
        let url = stagedBundleRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let prefix = stagedBundleRoot.path.hasSuffix("/")
            ? stagedBundleRoot.path
            : stagedBundleRoot.path + "/"
        guard !relativePath.hasPrefix("/"), url.path.hasPrefix(prefix) else {
            throw BundleOwnedProductUpdateInputReadError
                .pathEscapesStagedBundle(relativePath: relativePath)
        }
        return url
    }

    private func requireMissing(_ url: URL) throws {
        switch operations.pathState(url) {
        case .missing:
            return
        case .file:
            throw ExistingEffectPath(path: url.path, state: "file")
        case .directory:
            throw ExistingEffectPath(path: url.path, state: "directory")
        case .other(let state), .unknown(let state):
            throw ExistingEffectPath(path: url.path, state: state)
        case .inspectFailed(let reason):
            throw EffectPathInspectionFailure(path: url.path, reason: reason)
        }
    }

    private func readReceipt(
        at url: URL
    ) -> Result<ProductUpdateLayerEffectReceipt, EffectReceiptReadError> {
        switch operations.pathState(url) {
        case .file:
            break
        case .missing:
            return .failure(.init(reason: "receipt is missing"))
        case .directory:
            return .failure(.init(reason: "receipt path is a directory"))
        case .other(let state), .unknown(let state):
            return .failure(
                .init(reason: "receipt path state is \(state)")
            )
        case .inspectFailed(let reason):
            return .failure(
                .init(reason: "receipt inspection failed: \(reason)")
            )
        }
        do {
            let size = try operations.fileSize(url)
            guard size <= Self.maximumReceiptBytes else {
                return .failure(
                    .init(
                        reason:
                            "receipt exceeds \(Self.maximumReceiptBytes) bytes: \(size)"
                    )
                )
            }
            let data = try operations.readData(url)
            guard UInt64(data.count) <= Self.maximumReceiptBytes else {
                return .failure(
                    .init(
                        reason:
                            "receipt exceeds \(Self.maximumReceiptBytes) bytes: \(data.count)"
                    )
                )
            }
            return .success(
                try JSONDecoder().decode(
                    ProductUpdateLayerEffectReceipt.self,
                    from: data
                )
            )
        } catch {
            return .failure(
                .init(reason: "receipt read or decode failed: \(error)")
            )
        }
    }
}

private struct ExistingEffectPath: Error, CustomStringConvertible {
    let path: String
    let state: String
    var description: String {
        "effect path already exists path=\(path) state=\(state)"
    }
}

private struct EffectPathInspectionFailure: Error, CustomStringConvertible {
    let path: String
    let reason: String
    var description: String {
        "effect path inspection failed path=\(path) reason=\(reason)"
    }
}

private struct EffectReceiptReadError: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}
