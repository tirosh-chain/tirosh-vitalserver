import Application
import Contracts
import Foundation
import Errors

public struct RuntimeBundlePreparationVerification: Equatable, Sendable {
    public let sourceURL: URL
    public let bundleURL: URL
    public let manifest: UpdateBundleManifest

    public init(sourceURL: URL, bundleURL: URL, manifest: UpdateBundleManifest) {
        self.sourceURL = sourceURL
        self.bundleURL = bundleURL
        self.manifest = manifest
    }
}

public struct RuntimeBundlePreparationStageResult: Equatable, Sendable {
    public let sourceURL: URL
    public let bundleURL: URL
    public let destinationURL: URL
    public let manifest: UpdateBundleManifest

    public init(
        sourceURL: URL,
        bundleURL: URL,
        destinationURL: URL,
        manifest: UpdateBundleManifest
    ) {
        self.sourceURL = sourceURL
        self.bundleURL = bundleURL
        self.destinationURL = destinationURL
        self.manifest = manifest
    }
}

public struct RuntimeBundlePreparationWorkflowOperations {
    public let materialize: (URL) throws -> RuntimeMaterializedBundle
    public let cleanupTemporaryRoot: (URL) -> Void
    public let verifyDirectory: (URL, URL) throws -> UpdateBundleManifest
    public let stageBundle: (RuntimeBundleStagingInput) throws -> URL
    public let log: (String) -> Void

    public init(
        materialize: @escaping (URL) throws -> RuntimeMaterializedBundle,
        cleanupTemporaryRoot: @escaping (URL) -> Void,
        verifyDirectory: @escaping (URL, URL) throws -> UpdateBundleManifest,
        stageBundle: @escaping (RuntimeBundleStagingInput) throws -> URL,
        log: @escaping (String) -> Void
    ) {
        self.materialize = materialize
        self.cleanupTemporaryRoot = cleanupTemporaryRoot
        self.verifyDirectory = verifyDirectory
        self.stageBundle = stageBundle
        self.log = log
    }
}

public struct RuntimeBundlePreparationWorkflow {
    public let operations: RuntimeBundlePreparationWorkflowOperations
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(operations: RuntimeBundlePreparationWorkflowOperations) {
        self.operations = operations
    }

    public func verifyBundle(_ sourceURL: URL) throws -> RuntimeBundlePreparationVerification {
        operations.log(useCase.bundleVerificationStartedLogMessage(sourcePath: sourceURL.path))
        let materialized = try operations.materialize(sourceURL)
        defer { cleanupTemporaryRootIfNeeded(materialized) }
        let manifest = try operations.verifyDirectory(materialized.bundleURL, sourceURL)
        return RuntimeBundlePreparationVerification(
            sourceURL: sourceURL,
            bundleURL: materialized.bundleURL,
            manifest: manifest
        )
    }

    @discardableResult
    public func stageBundle(_ sourceURL: URL) throws -> RuntimeBundlePreparationStageResult {
        operations.log(useCase.bundleStageStartedLogMessage(sourcePath: sourceURL.path))
        let materialized = try operations.materialize(sourceURL)
        defer { cleanupTemporaryRootIfNeeded(materialized) }
        let manifest = try operations.verifyDirectory(materialized.bundleURL, sourceURL)
        let destination = try operations.stageBundle(RuntimeBundleStagingInput(
            sourceURL: sourceURL,
            bundleURL: materialized.bundleURL,
            manifestVersion: manifest.version
        ))
        return RuntimeBundlePreparationStageResult(
            sourceURL: sourceURL,
            bundleURL: materialized.bundleURL,
            destinationURL: destination,
            manifest: manifest
        )
    }

    private func cleanupTemporaryRootIfNeeded(_ materialized: RuntimeMaterializedBundle) {
        guard let temporaryRoot = materialized.temporaryRoot else {
            return
        }
        operations.cleanupTemporaryRoot(temporaryRoot)
    }
}
