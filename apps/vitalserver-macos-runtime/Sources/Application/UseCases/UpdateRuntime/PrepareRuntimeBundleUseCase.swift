import Contracts
import Foundation

public enum RuntimeBundleMaterializationCleanupPlan: Equatable, Sendable {
    case none
    case cleanupTemporaryRoot(URL)
}

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

public struct RuntimeBundlePreparationOperations {
    public let materialize: (URL) throws -> RuntimeMaterializedBundle
    public let executeMaterializationCleanupPlan: (RuntimeBundleMaterializationCleanupPlan) -> Void
    public let verifyDirectory: (URL, URL) throws -> UpdateBundleManifest
    public let stageBundle: (RuntimeBundleStagingInput) throws -> URL
    public let log: (String) -> Void

    public init(
        materialize: @escaping (URL) throws -> RuntimeMaterializedBundle,
        executeMaterializationCleanupPlan: @escaping (RuntimeBundleMaterializationCleanupPlan) -> Void,
        verifyDirectory: @escaping (URL, URL) throws -> UpdateBundleManifest,
        stageBundle: @escaping (RuntimeBundleStagingInput) throws -> URL,
        log: @escaping (String) -> Void
    ) {
        self.materialize = materialize
        self.executeMaterializationCleanupPlan = executeMaterializationCleanupPlan
        self.verifyDirectory = verifyDirectory
        self.stageBundle = stageBundle
        self.log = log
    }
}

public struct PrepareRuntimeBundleUseCase {
    public init() {}

    public func verifyBundle(
        _ sourceURL: URL,
        operations: RuntimeBundlePreparationOperations
    ) throws -> RuntimeBundlePreparationVerification {
        operations.log(bundleVerificationStartedLogMessage(sourcePath: sourceURL.path))
        let materialized = try operations.materialize(sourceURL)
        defer { cleanupTemporaryRootIfNeeded(materialized, operations: operations) }
        let manifest = try operations.verifyDirectory(materialized.bundleURL, sourceURL)
        return RuntimeBundlePreparationVerification(
            sourceURL: sourceURL,
            bundleURL: materialized.bundleURL,
            manifest: manifest
        )
    }

    @discardableResult
    public func stageBundle(
        _ sourceURL: URL,
        operations: RuntimeBundlePreparationOperations
    ) throws -> RuntimeBundlePreparationStageResult {
        operations.log(bundleStageStartedLogMessage(sourcePath: sourceURL.path))
        let materialized = try operations.materialize(sourceURL)
        defer { cleanupTemporaryRootIfNeeded(materialized, operations: operations) }
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

    public func bundleVerificationStartedLogMessage(sourcePath: String) -> String {
        "bundle verification started path=\(sourcePath)"
    }

    public func bundleStageStartedLogMessage(sourcePath: String) -> String {
        "bundle stage started source=\(sourcePath)"
    }

    public func bundleMaterializationCleanupPlan(
        materialized: RuntimeMaterializedBundle
    ) -> RuntimeBundleMaterializationCleanupPlan {
        guard let temporaryRoot = materialized.temporaryRoot else {
            return .none
        }
        return .cleanupTemporaryRoot(temporaryRoot)
    }

    private func cleanupTemporaryRootIfNeeded(
        _ materialized: RuntimeMaterializedBundle,
        operations: RuntimeBundlePreparationOperations
    ) {
        operations.executeMaterializationCleanupPlan(
            bundleMaterializationCleanupPlan(materialized: materialized)
        )
    }
}
