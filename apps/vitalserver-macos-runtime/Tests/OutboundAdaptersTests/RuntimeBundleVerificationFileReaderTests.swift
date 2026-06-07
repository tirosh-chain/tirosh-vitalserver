import Contracts
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
                parseChecksums: { _ in [:] }
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
                parseChecksums: { _ in [:] }
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
                parseChecksums: { text in
                    Dictionary(uniqueKeysWithValues: text
                        .split(separator: "\n")
                        .compactMap { line in
                            let parts = line.split(separator: " ", maxSplits: 1)
                            guard parts.count == 2 else {
                                return nil
                            }
                            return (String(parts[1]), String(parts[0]))
                        })
                }
            )
        )

        let checksums = try reader.loadChecksums(URL(fileURLWithPath: "/bundle/checksums.txt"))

        XCTAssertEqual(checksums, [
            "app.tar.gz": "abc",
            "migrations/001.sql": "def",
        ])
    }

    func testSHA256ReadsExplicitFileData() throws {
        let reader = RuntimeBundleVerificationFileReader(
            operations: RuntimeBundleVerificationFileReaderOperations(
                readData: { _ in Data("hello".utf8) },
                readUTF8Text: { _ in "" },
                parseChecksums: { _ in [:] }
            )
        )

        let digest = try reader.sha256(URL(fileURLWithPath: "/bundle/app.tar.gz"))

        XCTAssertEqual(digest, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
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
