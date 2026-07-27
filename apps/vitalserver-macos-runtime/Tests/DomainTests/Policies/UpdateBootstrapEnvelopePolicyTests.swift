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

    private func envelope(
        productId: String = "ai.tirosh.vitalserver.helper",
        layerOrder: [UpdateLayer] = [.guestRuntime, .container, .hostPlatform],
        nextUpdaterArtifact: UpdateBootstrapArtifact? = nil
    ) -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v1",
            id: "helper-release-bootstrap-022",
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
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: "2026-07-27T00:00:00Z"
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
