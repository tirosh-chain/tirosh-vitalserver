import Contracts
import Domain
import XCTest

final class UpdateBootstrapEnvelopePolicyTests: XCTestCase {
    func testAcceptsMatchingHelperTargetWithHostPlatformLast() throws {
        try UpdateBootstrapEnvelopePolicy.validate(
            envelope(),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )
    }

    func testRejectsDifferentProductOwner() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(productId: "vitalserver-runtime-platform"),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .productMismatch(
                    expected: "ai.tirosh.vitalserver.helper",
                    actual: "vitalserver-runtime-platform"
                )
            )
        }
    }

    func testRejectsHostPlatformBeforeAnotherLayer() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(layerOrder: [.hostPlatform, .guestRuntime]),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .hostPlatformMustBeLast
            )
        }
    }

    func testRejectsRepeatedLayer() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(layerOrder: [.guestRuntime, .guestRuntime]),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .duplicateLayer(.guestRuntime)
            )
        }
    }

    func testRejectsUnsafeArtifactPath() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(nextUpdaterArtifact: artifact(relativePath: "payload/../next-updater")),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .invalidArtifactPath(
                    artifactId: "next-updater",
                    relativePath: "payload/../next-updater"
                )
            )
        }
    }

    func testRejectsNonASCIISignedIdentifier() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(id: "helper-update-한글"),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .invalidIdentifier(field: "id", value: "helper-update-한글")
            )
        }
    }

    func testRejectsNonCanonicalIssuedAt() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(issuedAt: "2026-07-27 00:00:00+00:00"),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .invalidIssuedAt("2026-07-27 00:00:00+00:00")
            )
        }
    }

    func testRejectsIssuedAtThatIsNotARealUTCInstant() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(issuedAt: "2026-02-30T00:00:00Z"),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .invalidIssuedAt("2026-02-30T00:00:00Z")
            )
        }
    }

    func testRejectsV1SchemaVersion() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(schemaVersion: "v1"),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .unsupportedSchemaVersion("v1")
            )
        }
    }

    func testRejectsEmptyPayloadArtifacts() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(payloadArtifacts: []),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .emptyPayloadArtifacts
            )
        }
    }

    func testRejectsDuplicatePayloadArtifactPath() {
        let duplicate = UpdateBootstrapArtifact(
            id: "host-platform-apply-2",
            relativePath: "payload/layers/host-platform/apply.bin",
            sha256: String(repeating: "f", count: 64),
            sizeBytes: 31,
            mediaType: "application/octet-stream"
        )
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(payloadArtifacts: [
                UpdateBootstrapArtifact(
                    id: "host-platform-apply",
                    relativePath: "payload/layers/host-platform/apply.bin",
                    sha256: String(repeating: "d", count: 64),
                    sizeBytes: 30,
                    mediaType: "application/octet-stream"
                ),
                duplicate,
            ]),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .duplicatePayloadArtifactPath(
                    "payload/layers/host-platform/apply.bin"
                )
            )
        }
    }

    func testRejectsDuplicatePayloadArtifactId() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(payloadArtifacts: [
                UpdateBootstrapArtifact(
                    id: "host-platform-apply",
                    relativePath: "payload/layers/host-platform/apply.bin",
                    sha256: String(repeating: "d", count: 64),
                    sizeBytes: 30,
                    mediaType: "application/octet-stream"
                ),
                UpdateBootstrapArtifact(
                    id: "host-platform-apply",
                    relativePath: "payload/layers/host-platform/rollback.bin",
                    sha256: String(repeating: "e", count: 64),
                    sizeBytes: 31,
                    mediaType: "application/octet-stream"
                ),
            ]),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .duplicatePayloadArtifactId("host-platform-apply")
            )
        }
    }

    func testRejectsPayloadArtifactConflictsWithBootstrap() {
        XCTAssertThrowsError(try UpdateBootstrapEnvelopePolicy.validate(
            envelope(payloadArtifacts: [
                UpdateBootstrapArtifact(
                    id: "host-platform-apply",
                    relativePath: "payload/product-update.json",
                    sha256: String(repeating: "d", count: 64),
                    sizeBytes: 30,
                    mediaType: "application/json"
                ),
            ]),
            expectedProductId: "ai.tirosh.vitalserver.helper",
            expectedTarget: UpdateBootstrapTarget(platform: .macos, architecture: .arm64)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapEnvelopeValidationError,
                .payloadArtifactConflictsWithBootstrap(
                    relativePath: "payload/product-update.json"
                )
            )
        }
    }

    private func envelope(
        schemaVersion: String = "v2",
        id: String = "helper-release-bootstrap-022",
        productId: String = "ai.tirosh.vitalserver.helper",
        layerOrder: [UpdateLayer] = [.guestRuntime, .container, .hostPlatform],
        nextUpdaterArtifact: UpdateBootstrapArtifact? = nil,
        payloadArtifacts: [UpdateBootstrapArtifact]? = nil,
        issuedAt: String = "2026-07-27T00:00:00Z"
    ) -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: schemaVersion,
            id: id,
            productId: productId,
            target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: layerOrder,
            nextUpdaterArtifact: nextUpdaterArtifact ?? artifact(relativePath: "payload/next-updater"),
            specification: UpdateBootstrapArtifact(
                id: "product-update",
                relativePath: "payload/product-update.json",
                sha256: String(repeating: "b", count: 64),
                sizeBytes: 91,
                mediaType: "application/json"
            ),
            payloadArtifacts: payloadArtifacts ?? [
                UpdateBootstrapArtifact(
                    id: "host-platform-apply",
                    relativePath: "payload/layers/host-platform/apply.bin",
                    sha256: String(repeating: "d", count: 64),
                    sizeBytes: 30,
                    mediaType: "application/octet-stream"
                ),
            ],
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: issuedAt
        )
    }

    private func artifact(relativePath: String) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: "next-updater",
            relativePath: relativePath,
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 42,
            mediaType: "application/octet-stream"
        )
    }
}
