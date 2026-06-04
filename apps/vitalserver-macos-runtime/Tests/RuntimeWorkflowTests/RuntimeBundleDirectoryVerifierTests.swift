import Contracts
import Core
import Foundation
import RuntimeWorkflow
import XCTest

final class RuntimeBundleDirectoryVerifierTests: XCTestCase {
    func testVerifyRunsManifestChecksumArtifactAndMigrationChecksInOrder() throws {
        let bundleURL = URL(fileURLWithPath: "/bundle")
        let sourceURL = URL(fileURLWithPath: "/input/update-bundle")
        let manifest = makeManifest()
        var events: [String] = []
        let verifier = RuntimeBundleDirectoryVerifier(
            context: RuntimeBundleDirectoryVerificationContext(
                manifestFileName: "manifest.json",
                checksumsFileName: "checksums.txt",
                signatureFileName: "signature"
            ),
            operations: RuntimeBundleDirectoryVerificationOperations(
                requireDirectory: { url in events.append("dir:\(url.path)") },
                requireFile: { url in events.append("file:\(url.path)") },
                loadManifest: { url in
                    events.append("manifest:\(url.path)")
                    return manifest
                },
                makeVerificationPlan: { manifest in
                    events.append("plan:\(manifest.version)")
                    return UpdateBundleVerificationPlan(
                        artifactFiles: [
                            UpdateBundleFileVerification(
                                name: "app.tar.gz",
                                checksumKey: "app.tar.gz",
                                expectedSHA256: "abc",
                                expectedSize: 10
                            ),
                        ],
                        migrationFiles: [
                            UpdateBundleFileVerification(
                                name: "001.sql",
                                checksumKey: "migrations/001.sql",
                                expectedSHA256: "def",
                                expectedSize: 20
                            ),
                        ]
                    )
                },
                loadChecksums: { url in
                    events.append("checksums:\(url.path)")
                    return ["app.tar.gz": "abc", "migrations/001.sql": "def"]
                },
                verifyDigest: { url, verification, checksumMap in
                    events.append("digest:\(url.path):\(verification.checksumKey):\(checksumMap.count)")
                },
                validateArtifactPayload: { artifact, url in
                    events.append("payload:\(artifact.name):\(url.path)")
                },
                log: { message in
                    events.append("log:\(message)")
                }
            )
        )

        let verifiedManifest = try verifier.verify(bundleURL: bundleURL, sourceURL: sourceURL)

        XCTAssertEqual(verifiedManifest, manifest)
        XCTAssertEqual(events, [
            "dir:/bundle",
            "file:/bundle/manifest.json",
            "file:/bundle/checksums.txt",
            "file:/bundle/signature",
            "manifest:/bundle/manifest.json",
            "plan:1.2.3",
            "log:bundle manifest loaded version=1.2.3 runtimeVersion=1.2.3 artifacts=1 migrations=1",
            "checksums:/bundle/checksums.txt",
            "file:/bundle/app.tar.gz",
            "log:verifying artifact type=app-bundle name=app.tar.gz size=0.0 MiB",
            "digest:/bundle/app.tar.gz:app.tar.gz:2",
            "payload:app.tar.gz:/bundle/app.tar.gz",
            "file:/bundle/migrations/001.sql",
            "log:verifying migration name=001.sql size=0.0 MiB",
            "digest:/bundle/migrations/001.sql:migrations/001.sql:2",
            "log:bundle verification completed path=/input/update-bundle",
        ])
    }

    func testVerifyStopsBeforeManifestLoadWhenRequiredFileIsMissing() {
        let bundleURL = URL(fileURLWithPath: "/bundle")
        var loadedManifest = false
        let verifier = RuntimeBundleDirectoryVerifier(
            context: RuntimeBundleDirectoryVerificationContext(
                manifestFileName: "manifest.json",
                checksumsFileName: "checksums.txt",
                signatureFileName: "signature"
            ),
            operations: RuntimeBundleDirectoryVerificationOperations(
                requireDirectory: { _ in },
                requireFile: { url in
                    if url.lastPathComponent == "checksums.txt" {
                        throw TestBundleDirectoryVerifierError.missingFile(url.path)
                    }
                },
                loadManifest: { _ in
                    loadedManifest = true
                    return self.makeManifest()
                },
                makeVerificationPlan: { _ in UpdateBundleVerificationPlan(artifactFiles: [], migrationFiles: []) },
                loadChecksums: { _ in [:] },
                verifyDigest: { _, _, _ in },
                validateArtifactPayload: { _, _ in },
                log: { _ in }
            )
        )

        XCTAssertThrowsError(try verifier.verify(bundleURL: bundleURL, sourceURL: bundleURL)) { error in
            XCTAssertEqual(
                error as? TestBundleDirectoryVerifierError,
                .missingFile("/bundle/checksums.txt")
            )
        }
        XCTAssertFalse(loadedManifest)
    }

    private func makeManifest() -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["runtime": "1.2.3"],
            createdAt: "2026-06-05T00:00:00Z",
            artifacts: [
                UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10),
            ],
            migrations: [
                UpdateBundleMigration(name: "001.sql", sha256: "def", size: 20),
            ]
        )
    }
}

private enum TestBundleDirectoryVerifierError: Error, Equatable {
    case missingFile(String)
}
