import Contracts
import Foundation
import Errors

public struct RuntimeBundleDirectoryVerificationContext: Equatable, Sendable {
    public let manifestFileName: String
    public let checksumsFileName: String
    public let signatureFileName: String

    public init(
        manifestFileName: String,
        checksumsFileName: String,
        signatureFileName: String
    ) {
        self.manifestFileName = manifestFileName
        self.checksumsFileName = checksumsFileName
        self.signatureFileName = signatureFileName
    }
}

public struct RuntimeBundleDirectoryVerificationOperations {
    public let requireDirectory: (URL) throws -> Void
    public let requireFile: (URL) throws -> Void
    public let loadManifest: (URL) throws -> UpdateBundleManifest
    public let makeVerificationPlan: (UpdateBundleManifest) throws -> UpdateBundleVerificationPlan
    public let loadChecksums: (URL) throws -> [String: String]
    public let verifyDigest: (URL, UpdateBundleFileVerification, [String: String]) throws -> Void
    public let validateArtifactPayload: (UpdateBundleArtifact, URL) throws -> Void
    public let log: (String) -> Void

    public init(
        requireDirectory: @escaping (URL) throws -> Void,
        requireFile: @escaping (URL) throws -> Void,
        loadManifest: @escaping (URL) throws -> UpdateBundleManifest,
        makeVerificationPlan: @escaping (UpdateBundleManifest) throws -> UpdateBundleVerificationPlan,
        loadChecksums: @escaping (URL) throws -> [String: String],
        verifyDigest: @escaping (URL, UpdateBundleFileVerification, [String: String]) throws -> Void,
        validateArtifactPayload: @escaping (UpdateBundleArtifact, URL) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireDirectory = requireDirectory
        self.requireFile = requireFile
        self.loadManifest = loadManifest
        self.makeVerificationPlan = makeVerificationPlan
        self.loadChecksums = loadChecksums
        self.verifyDigest = verifyDigest
        self.validateArtifactPayload = validateArtifactPayload
        self.log = log
    }
}

public struct RuntimeBundleDirectoryVerifier {
    public let context: RuntimeBundleDirectoryVerificationContext
    public let operations: RuntimeBundleDirectoryVerificationOperations

    public init(
        context: RuntimeBundleDirectoryVerificationContext,
        operations: RuntimeBundleDirectoryVerificationOperations
    ) {
        self.context = context
        self.operations = operations
    }

    @discardableResult
    public func verify(bundleURL: URL, sourceURL: URL) throws -> UpdateBundleManifest {
        let manifestURL = bundleURL.appendingPathComponent(context.manifestFileName)
        let checksumsURL = bundleURL.appendingPathComponent(context.checksumsFileName)
        let signatureURL = bundleURL.appendingPathComponent(context.signatureFileName)

        try operations.requireDirectory(bundleURL)
        for url in [manifestURL, checksumsURL, signatureURL] {
            try operations.requireFile(url)
        }

        let manifest = try operations.loadManifest(manifestURL)
        let plan = try operations.makeVerificationPlan(manifest)
        operations.log(
            "bundle manifest loaded version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)"
        )

        let checksumMap = try operations.loadChecksums(checksumsURL)
        for (artifact, fileVerification) in zip(manifest.artifacts, plan.artifactFiles) {
            let artifactURL = bundleURL.appendingPathComponent(fileVerification.name)
            try operations.requireFile(artifactURL)

            operations.log(
                "verifying artifact type=\(artifact.type.rawValue) name=\(artifact.name) size=\(formatBytes(bundleItemSize(artifact.size)))"
            )
            try operations.verifyDigest(artifactURL, fileVerification, checksumMap)
            try operations.validateArtifactPayload(artifact, artifactURL)
        }

        for (migration, fileVerification) in zip(manifest.migrations, plan.migrationFiles) {
            let migrationURL = bundleURL.appendingPathComponent(fileVerification.checksumKey)
            try operations.requireFile(migrationURL)

            operations.log("verifying migration name=\(migration.name) size=\(formatBytes(bundleItemSize(migration.size)))")
            try operations.verifyDigest(migrationURL, fileVerification, checksumMap)
        }

        operations.log(
            "bundle integrity checked publisherAuthenticity=unverified path=\(sourceURL.path)"
        )
        return manifest
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func bundleItemSize(_ size: Int) -> UInt64 {
        UInt64(max(size, 0))
    }
}
