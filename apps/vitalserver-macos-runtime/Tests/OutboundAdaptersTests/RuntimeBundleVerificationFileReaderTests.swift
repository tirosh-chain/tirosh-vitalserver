import Contracts
import Domain
import Foundation
import OutboundAdapters
import XCTest

final class RuntimeBundleVerificationFileReaderTests: XCTestCase {
    func testLoadManifestDecodesManifestFromExplicitFileData() throws {
        let manifest = makeManifest()
        let data = try JSONEncoder().encode(manifest)
        let reader = RuntimeBundleVerificationFileReader(
            operations: RuntimeBundleVerificationFileReaderOperations(
                readData: { url in
                    XCTAssertEqual(url.path, "/bundle/manifest.json")
                    return data
                },
                readUTF8Text: { _ in "" },
                fileSize: { _ in 0 },
                log: { _ in }
            )
        )

        let loaded = try reader.loadManifest(URL(fileURLWithPath: "/bundle/manifest.json"))

        XCTAssertEqual(loaded, manifest)
    }

    func testLoadManifestPropagatesDecodeFailureWithoutEmptyManifestFallback() {
        let reader = RuntimeBundleVerificationFileReader(
            operations: RuntimeBundleVerificationFileReaderOperations(
                readData: { _ in Data("not json".utf8) },
                readUTF8Text: { _ in "" },
                fileSize: { _ in 0 },
                log: { _ in }
            )
        )

        XCTAssertThrowsError(try reader.loadManifest(URL(fileURLWithPath: "/bundle/manifest.json"))) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testLoadChecksumsParsesExplicitChecksumFileText() throws {
        let reader = RuntimeBundleVerificationFileReader(
            operations: RuntimeBundleVerificationFileReaderOperations(
                readData: { _ in Data() },
                readUTF8Text: { _ in "abc app.tar.gz\ndef migrations/001.sql\n" },
                fileSize: { _ in 0 },
                log: { _ in }
            )
        )

        let checksums = try reader.loadChecksums(URL(fileURLWithPath: "/bundle/checksums.txt"))

        XCTAssertEqual(checksums, [
            "app.tar.gz": "abc",
            "migrations/001.sql": "def",
        ])
    }

    func testVerifyDigestPreservesExplicitVerificationErrorWithoutSuccessFallback() {
        let reader = RuntimeBundleVerificationFileReader(
            operations: RuntimeBundleVerificationFileReaderOperations(
                readData: { _ in Data("hello".utf8) },
                readUTF8Text: { _ in "" },
                fileSize: { _ in 5 },
                log: { _ in }
            )
        )

        XCTAssertThrowsError(try reader.verifyDigest(
            url: URL(fileURLWithPath: "/bundle/app.tar.gz"),
            fileVerification: UpdateBundleFileVerification(
                name: "app.tar.gz",
                checksumKey: "app.tar.gz",
                expectedSHA256: "not-the-actual-digest",
                expectedSize: 5
            ),
            checksumMap: ["app.tar.gz": "not-the-actual-digest"]
        )) { error in
            XCTAssertEqual(
                error as? UpdateBundleVerificationError,
                .manifestChecksumMismatch("app.tar.gz")
            )
        }
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
