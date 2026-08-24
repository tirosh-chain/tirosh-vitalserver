import Contracts
import XCTest

final class UpdateBootstrapEnvelopeContractsTests: XCTestCase {
    func testDecodesStableHelperBootstrapEnvelope() throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(
                forResource: "update-bootstrap-envelope-v2",
                withExtension: "json"
            )
        )

        let envelope = try JSONDecoder().decode(
            UpdateBootstrapEnvelope.self,
            from: Data(contentsOf: fixture)
        )

        XCTAssertEqual(envelope.schemaVersion, "v2")
        XCTAssertEqual(envelope.id, "helper-release-bootstrap-022")
        XCTAssertEqual(envelope.productId, "ai.tirosh.vitalserver.helper")
        XCTAssertEqual(envelope.target, UpdateBootstrapTarget(platform: .macos, architecture: .arm64))
        XCTAssertEqual(envelope.targetRelease.productVersion, "0.2.2")
        XCTAssertEqual(envelope.layerOrder, [.guestRuntime, .container, .hostPlatform])
        XCTAssertEqual(envelope.nextUpdaterArtifact.relativePath, "payload/vitalserver-next-updater")
        XCTAssertEqual(envelope.specification.relativePath, "payload/product-update.json")
        XCTAssertEqual(envelope.payloadArtifacts.count, 1)
        XCTAssertEqual(envelope.payloadArtifacts[0].id, "host-platform-apply")
        XCTAssertEqual(envelope.signature.algorithm, .ed25519)
        XCTAssertEqual(envelope.signature.keyId, "helper-release-key-2026")
    }

    func testRejectsLegacyUpdaterCompatibilityFields() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            UpdateBootstrapEnvelope.self,
            from: Data("""
            {
              "schemaVersion": "v2",
              "id": "helper-release-bootstrap-022",
              "productId": "ai.tirosh.vitalserver.helper",
              "target": { "platform": "macos", "architecture": "arm64" },
              "targetRelease": { "productVersion": "0.2.2", "runtimeVersion": "0.2.2" },
              "layerOrder": ["host-platform"],
              "nextUpdaterArtifact": {
                "id": "next-updater",
                "relativePath": "payload/next-updater",
                "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "sizeBytes": 42,
                "mediaType": "application/octet-stream"
              },
              "specification": {
                "id": "product-update",
                "relativePath": "payload/product-update.json",
                "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                "sizeBytes": 91,
                "mediaType": "application/json"
              },
              "payloadArtifacts": [
                {
                  "id": "host-platform-apply",
                  "relativePath": "payload/layers/host-platform/apply.bin",
                  "sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
                  "sizeBytes": 7,
                  "mediaType": "application/octet-stream"
                }
              ],
              "signature": {
                "algorithm": "ed25519",
                "keyId": "release-key",
                "signedSha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "value": "signature"
              },
              "issuedAt": "2026-07-27T00:00:00Z",
              "minUpdaterVersion": "0.2.1",
              "requiresTwoPhaseUpdate": true
            }
            """.utf8)
        )) { error in
            XCTAssertEqual(
                unsupportedFieldsDescription(error),
                "UpdateBootstrapEnvelope contains unsupported fields: minUpdaterVersion,requiresTwoPhaseUpdate"
            )
        }
    }

    func testRejectsUnknownNestedArtifactField() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            UpdateBootstrapEnvelope.self,
            from: Data("""
            {
              "schemaVersion": "v2",
              "id": "helper-release-bootstrap-022",
              "productId": "ai.tirosh.vitalserver.helper",
              "target": { "platform": "macos", "architecture": "arm64" },
              "targetRelease": { "productVersion": "0.2.2", "runtimeVersion": "0.2.2" },
              "layerOrder": ["host-platform"],
              "nextUpdaterArtifact": {
                "id": "next-updater",
                "relativePath": "payload/next-updater",
                "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "sizeBytes": 42,
                "mediaType": "application/octet-stream",
                "command": "do-not-infer-a-command"
              },
              "specification": {
                "id": "product-update",
                "relativePath": "payload/product-update.json",
                "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                "sizeBytes": 91,
                "mediaType": "application/json"
              },
              "payloadArtifacts": [
                {
                  "id": "host-platform-apply",
                  "relativePath": "payload/layers/host-platform/apply.bin",
                  "sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
                  "sizeBytes": 7,
                  "mediaType": "application/octet-stream"
                }
              ],
              "signature": {
                "algorithm": "ed25519",
                "keyId": "release-key",
                "signedSha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "value": "signature"
              },
              "issuedAt": "2026-07-27T00:00:00Z"
            }
            """.utf8)
        )) { error in
            XCTAssertEqual(
                unsupportedFieldsDescription(error),
                "UpdateBootstrapArtifact contains unsupported fields: command"
            )
        }
    }

    private func unsupportedFieldsDescription(_ error: Error) -> String? {
        guard case DecodingError.dataCorrupted(let context) = error else {
            return nil
        }
        return context.debugDescription
    }
}
