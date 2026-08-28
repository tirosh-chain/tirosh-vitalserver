import Application
import Contracts
import CryptoKit
import Foundation
import OutboundAdapters
import XCTest

final class UpdateBootstrapVerificationAdaptersTests: XCTestCase {
    func testCanonicalPayloadMatchesTheCrossPlatformFieldOrder() throws {
        let payload = try UpdateBootstrapCanonicalPayloadEncoder().encode(envelope())

        XCTAssertEqual(
            String(decoding: payload, as: UTF8.self),
            """
            {"schemaVersion":"v2","id":"helper-update-0.2.2","productId":"ai.tirosh.vitalserver.helper","target":{"platform":"macos","architecture":"arm64"},"targetRelease":{"productVersion":"0.2.2","runtimeVersion":"0.2.2"},"layerOrder":["container","guest-runtime","host-platform"],"nextUpdaterArtifact":{"id":"helper-next-updater","relativePath":"payload/bin/vitalserver-update","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sizeBytes":7,"mediaType":"application/octet-stream"},"specification":{"id":"helper-update-specification","relativePath":"payload/update-specification.json","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sizeBytes":8,"mediaType":"application/json"},"payloadArtifacts":[],"issuedAt":"2026-07-27T00:00:00Z"}
            """
        )
    }

    func testVerifiesRealEd25519SignatureAndRejectsModifiedPayload() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = Data("signed bootstrap payload".utf8)
        let signature = try privateKey.signature(for: payload).base64EncodedString()
        let verifier = UpdateBootstrapPublisherSignatureVerifier(
            publisherKeysById: [
                "helper-release-key-2026": TrustedUpdatePublisherKey(
                    id: "helper-release-key-2026",
                    algorithm: .ed25519,
                    publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
                    state: .active
                )
            ]
        )

        XCTAssertEqual(
            verifier.verify(
                keyId: "helper-release-key-2026",
                algorithm: .ed25519,
                payload: payload,
                signature: signature
            ),
            .verified
        )
        XCTAssertEqual(
            verifier.verify(
                keyId: "helper-release-key-2026",
                algorithm: .ed25519,
                payload: Data("modified payload".utf8),
                signature: signature
            ),
            .invalidSignature
        )
    }

    func testRejectsRevokedAndUnknownPublisherKeysDistinctly() {
        let verifier = UpdateBootstrapPublisherSignatureVerifier(
            publisherKeysById: [
                "revoked-key": TrustedUpdatePublisherKey(
                    id: "revoked-key",
                    algorithm: .ed25519,
                    publicKey: Data(repeating: 0, count: 32).base64EncodedString(),
                    state: .revoked
                ),
            ]
        )

        XCTAssertEqual(
            verifier.verify(
                keyId: "revoked-key",
                algorithm: .ed25519,
                payload: Data(),
                signature: ""
            ),
            .keyRevoked(keyId: "revoked-key")
        )
        XCTAssertEqual(
            verifier.verify(
                keyId: "unknown-key",
                algorithm: .ed25519,
                payload: Data(),
                signature: ""
            ),
            .keyUnavailable(keyId: "unknown-key")
        )
    }

    func testObservesRegularArtifactAndRejectsSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let payloadDirectory = root.appendingPathComponent("payload")
        try FileManager.default.createDirectory(
            at: payloadDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let regular = payloadDirectory.appendingPathComponent("updater")
        try Data("updater".utf8).write(to: regular)
        let symlink = payloadDirectory.appendingPathComponent("updater-link")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: regular
        )
        let observer = UpdateBootstrapArtifactFileObserver(
            bundleDirectory: root
        )

        XCTAssertEqual(
            observer.observe(artifact(path: "payload/updater", size: 7)),
            .available(
                sha256: "196c23750e800642e7c008dc0416536449f295069c8161c23283c86334f8d251",
                sizeBytes: 7
            )
        )
        XCTAssertEqual(
            observer.observe(artifact(path: "payload/updater-link", size: 7)),
            .failed(reason: "artifact is not a regular file")
        )
    }

    private func artifact(path: String, size: Int) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: "helper-next-updater",
            relativePath: path,
            sha256: String(repeating: "a", count: 64),
            sizeBytes: size,
            mediaType: "application/octet-stream"
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v2",
            id: "helper-update-0.2.2",
            productId: "ai.tirosh.vitalserver.helper",
            target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: artifact(
                path: "payload/bin/vitalserver-update",
                size: 7
            ),
            specification: UpdateBootstrapArtifact(
                id: "helper-update-specification",
                relativePath: "payload/update-specification.json",
                sha256: String(repeating: "b", count: 64),
                sizeBytes: 8,
                mediaType: "application/json"
            ),
            payloadArtifacts: [],
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "helper-release-key-2026",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: "2026-07-27T00:00:00Z"
        )
    }
}
