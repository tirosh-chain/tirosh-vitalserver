import Core
import Contracts
import XCTest

final class UpdateBundleVerifierTests: XCTestCase {
    func testMakePlanValidatesContractAndBuildsArtifactAndMigrationEntries() throws {
        let manifest = manifest(
            artifacts: [
                UpdateBundleArtifact(name: "rootfs-base.raw.gz", type: .rootfsBase, sha256: "abc", size: 10),
                UpdateBundleArtifact(name: "guest-deploy.tar.gz", type: .guestDeploy, sha256: "def", size: 20),
            ],
            migrations: [
                UpdateBundleMigration(name: "001.sh", sha256: "123", size: 30),
            ]
        )

        let plan = try UpdateBundleVerifier.makePlan(
            manifest: manifest,
            expectedProduct: "com.tirosh.vitalserver"
        )

        XCTAssertEqual(plan.artifactFiles.map(\.checksumKey), [
            "rootfs-base.raw.gz",
            "guest-deploy.tar.gz",
        ])
        XCTAssertEqual(plan.migrationFiles.map(\.checksumKey), ["migrations/001.sh"])
    }

    func testMakePlanRejectsUnsupportedSchemaProductUnsafeNamesAndUnknownTypes() {
        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(schemaVersion: 1),
            expectedProduct: "com.tirosh.vitalserver"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .unsupportedSchema(1))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(product: "OtherProduct"),
            expectedProduct: "com.tirosh.vitalserver"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .unsupportedProduct("OtherProduct"))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(name: "../escape.tar.gz", type: .guestDeploy, sha256: "abc", size: 10),
            ]),
            expectedProduct: "com.tirosh.vitalserver"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .invalidArtifactName("../escape.tar.gz"))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(name: "future.tar.gz", type: .unknown("future"), sha256: "abc", size: 10),
            ]),
            expectedProduct: "com.tirosh.vitalserver"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .unsupportedArtifactType("future"))
        }
    }

    func testVerifyDigestChecksManifestDigestChecksumFileAndSize() throws {
        try UpdateBundleVerifier.verifyDigest(
            checksumKey: "rootfs-base.raw.gz",
            expectedSHA256: "abc",
            expectedSize: 10,
            checksumMap: ["rootfs-base.raw.gz": "abc"],
            actualSHA256: "abc",
            actualSize: 10
        )

        XCTAssertThrowsError(try UpdateBundleVerifier.verifyDigest(
            checksumKey: "rootfs-base.raw.gz",
            expectedSHA256: "abc",
            expectedSize: 10,
            checksumMap: ["rootfs-base.raw.gz": "abc"],
            actualSHA256: "def",
            actualSize: 10
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .manifestChecksumMismatch("rootfs-base.raw.gz"))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.verifyDigest(
            checksumKey: "rootfs-base.raw.gz",
            expectedSHA256: "abc",
            expectedSize: 10,
            checksumMap: ["rootfs-base.raw.gz": "def"],
            actualSHA256: "abc",
            actualSize: 10
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .checksumFileMismatch("rootfs-base.raw.gz"))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.verifyDigest(
            checksumKey: "rootfs-base.raw.gz",
            expectedSHA256: "abc",
            expectedSize: 10,
            checksumMap: ["rootfs-base.raw.gz": "abc"],
            actualSHA256: "abc",
            actualSize: 11
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .sizeMismatch("rootfs-base.raw.gz"))
        }
    }

    private func manifest(
        schemaVersion: Int = 3,
        product: String = "com.tirosh.vitalserver",
        artifacts: [UpdateBundleArtifact] = [
            UpdateBundleArtifact(name: "rootfs-base.raw.gz", type: .rootfsBase, sha256: "abc", size: 10),
        ],
        migrations: [UpdateBundleMigration] = []
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: schemaVersion,
            product: product,
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatforms: ["macos-arm64"],
            components: ["updater": "4.5.6"],
            createdAt: "2026-05-21T12:00:00Z",
            artifacts: artifacts,
            migrations: migrations
        )
    }
}
