import Contracts
import Errors
public struct UpdateBundleFileVerification: Equatable, Sendable {
    public let name: String
    public let checksumKey: String
    public let expectedSHA256: String
    public let expectedSize: Int

    public init(name: String, checksumKey: String, expectedSHA256: String, expectedSize: Int) {
        self.name = name
        self.checksumKey = checksumKey
        self.expectedSHA256 = expectedSHA256
        self.expectedSize = expectedSize
    }
}

public struct UpdateBundleVerificationPlan: Equatable, Sendable {
    public let artifactFiles: [UpdateBundleFileVerification]
    public let migrationFiles: [UpdateBundleFileVerification]

    public init(
        artifactFiles: [UpdateBundleFileVerification],
        migrationFiles: [UpdateBundleFileVerification]
    ) {
        self.artifactFiles = artifactFiles
        self.migrationFiles = migrationFiles
    }
}

public enum UpdateBundleVerifier {
    public static func makePlan(
        manifest: UpdateBundleManifest,
        expectedProduct: String
    ) throws -> UpdateBundleVerificationPlan {
        guard manifest.schemaVersion == 3 else {
            throw UpdateBundleVerificationError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.product == expectedProduct else {
            throw UpdateBundleVerificationError.unsupportedProduct(manifest.product)
        }

        let artifactFiles = try manifest.artifacts.map { artifact in
            guard isSafeBundleName(artifact.name) else {
                throw UpdateBundleVerificationError.invalidArtifactName(artifact.name)
            }
            guard !artifact.type.isUnknown else {
                throw UpdateBundleVerificationError.unsupportedArtifactType(artifact.type.rawValue)
            }
            return UpdateBundleFileVerification(
                name: artifact.name,
                checksumKey: artifact.name,
                expectedSHA256: artifact.sha256,
                expectedSize: artifact.size
            )
        }

        let migrationFiles = try manifest.migrations.map { migration in
            guard isSafeBundleName(migration.name) else {
                throw UpdateBundleVerificationError.invalidMigrationName(migration.name)
            }
            return UpdateBundleFileVerification(
                name: migration.name,
                checksumKey: "migrations/\(migration.name)",
                expectedSHA256: migration.sha256,
                expectedSize: migration.size
            )
        }

        return UpdateBundleVerificationPlan(
            artifactFiles: artifactFiles,
            migrationFiles: migrationFiles
        )
    }

    public static func verifyDigest(
        checksumKey: String,
        expectedSHA256: String,
        expectedSize: Int,
        checksumMap: [String: String],
        actualSHA256: String,
        actualSize: Int
    ) throws {
        guard actualSHA256 == expectedSHA256 else {
            throw UpdateBundleVerificationError.manifestChecksumMismatch(checksumKey)
        }
        guard checksumMap[checksumKey] == actualSHA256 else {
            throw UpdateBundleVerificationError.checksumFileMismatch(checksumKey)
        }
        guard actualSize == expectedSize else {
            throw UpdateBundleVerificationError.sizeMismatch(checksumKey)
        }
    }

    public static func isSafeBundleName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
    }
}

extension UpdateBundleArtifactType {
    public var isUnknown: Bool {
        if case .unknown = self {
            return true
        }
        return false
    }
}
