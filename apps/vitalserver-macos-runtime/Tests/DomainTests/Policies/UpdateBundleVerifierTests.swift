import Application
import Contracts
import Domain
import XCTest
import Errors

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
            expectedProduct: "ai.tirosh.vitalserver.helper"
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
            expectedProduct: "ai.tirosh.vitalserver.helper"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .unsupportedSchema(1))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(product: "OtherProduct"),
            expectedProduct: "ai.tirosh.vitalserver.helper"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .unsupportedProduct("OtherProduct"))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(name: "../escape.tar.gz", type: .guestDeploy, sha256: "abc", size: 10),
            ]),
            expectedProduct: "ai.tirosh.vitalserver.helper"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .invalidArtifactName("../escape.tar.gz"))
        }

        XCTAssertThrowsError(try UpdateBundleVerifier.makePlan(
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(name: "future.tar.gz", type: .unknown("future"), sha256: "abc", size: 10),
            ]),
            expectedProduct: "ai.tirosh.vitalserver.helper"
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

    func testChecksumFileParserBuildsChecksumMapAndIgnoresMalformedLines() {
        let checksums = UpdateBundleChecksumFileParser.parse(
            "abc123  rootfs-base.raw.gz\n"
                + "def456\tmigrations/001.sh\n"
                + "malformed\n"
                + "ghi789   artifacts/app.tar.gz   \n"
        )

        XCTAssertEqual(checksums, [
            "rootfs-base.raw.gz": "abc123",
            "migrations/001.sh": "def456",
            "artifacts/app.tar.gz": "ghi789",
        ])
    }

    private func manifest(
        schemaVersion: Int = 3,
        product: String = "ai.tirosh.vitalserver.helper",
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
            targetPlatform: "macos-arm64",
            components: ["updater": "4.5.6"],
            createdAt: "2026-05-21T12:00:00Z",
            artifacts: artifacts,
            migrations: migrations
        )
    }
}
