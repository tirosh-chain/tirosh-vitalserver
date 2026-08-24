import Contracts
import OutboundAdapters
import XCTest

final class UpdateBootstrapCanonicalPayloadEncoderTests: XCTestCase {
    func testCanonicalPayloadMatchesPythonBuilderContract() throws {
        let envelope = UpdateBootstrapEnvelope(
            schemaVersion: "v2",
            id: "helper-update-0.2.2",
            productId: "ai.tirosh.vitalserver.helper",
            target: UpdateBootstrapTarget(
                platform: .macos,
                architecture: .arm64
            ),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: UpdateBootstrapArtifact(
                id: "helper-next-updater",
                relativePath: "payload/bin/vitalserver-update",
                sha256: String(repeating: "a", count: 64),
                sizeBytes: 7,
                mediaType: "application/octet-stream"
            ),
            specification: UpdateBootstrapArtifact(
                id: "helper-update-specification",
                relativePath: "payload/update-specification.json",
                sha256: String(repeating: "b", count: 64),
                sizeBytes: 8,
                mediaType: "application/json"
            ),
            payloadArtifacts: [
                UpdateBootstrapArtifact(
                    id: "host-platform-apply",
                    relativePath: "payload/layers/host-platform/apply.bin",
                    sha256: String(repeating: "c", count: 64),
                    sizeBytes: 9,
                    mediaType: "application/octet-stream"
                ),
            ],
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "helper-release-key-2026",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: "2026-07-27T00:00:00Z"
        )

        let payload = try UpdateBootstrapCanonicalPayloadEncoder().encode(
            envelope
        )

        let expected =
            #"{"schemaVersion":"v2","id":"helper-update-0.2.2","productId":"ai.tirosh.vitalserver.helper","target":{"platform":"macos","architecture":"arm64"},"targetRelease":{"productVersion":"0.2.2","runtimeVersion":"0.2.2"},"layerOrder":["container","guest-runtime","host-platform"],"nextUpdaterArtifact":{"id":"helper-next-updater","relativePath":"payload/bin/vitalserver-update","sha256":"\#(String(repeating: "a", count: 64))","sizeBytes":7,"mediaType":"application/octet-stream"},"specification":{"id":"helper-update-specification","relativePath":"payload/update-specification.json","sha256":"\#(String(repeating: "b", count: 64))","sizeBytes":8,"mediaType":"application/json"},"payloadArtifacts":[{"id":"host-platform-apply","relativePath":"payload/layers/host-platform/apply.bin","sha256":"\#(String(repeating: "c", count: 64))","sizeBytes":9,"mediaType":"application/octet-stream"}],"issuedAt":"2026-07-27T00:00:00Z"}"#

        XCTAssertEqual(
            String(decoding: payload, as: UTF8.self),
            expected
        )
    }
}
