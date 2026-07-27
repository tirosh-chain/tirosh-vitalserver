import Application
import Contracts
import XCTest

final class VerifyUpdateBootstrapEnvelopeUseCaseTests: XCTestCase {
    func testReturnsVerifiedClosureOnlyAfterPublisherAndBothArtifactsAreVerified() throws {
        let harness = VerificationHarness()

        let closure = try harness.verify()

        XCTAssertEqual(closure.updateId, "helper-update-0.2.2")
        XCTAssertEqual(closure.canonicalPayloadSHA256, harness.envelope.signature.signedSha256)
        XCTAssertEqual(
            closure.verifiedArtifactIds,
            ["helper-next-updater", "helper-update-specification"]
        )
        XCTAssertEqual(harness.observedArtifactIds, closure.verifiedArtifactIds)
        XCTAssertEqual(harness.publisherVerificationCount, 1)
    }

    func testRejectsCanonicalPayloadDigestMismatchBeforePublisherVerification() {
        let harness = VerificationHarness()
        harness.canonicalPayloadSHA256 = String(repeating: "d", count: 64)

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapEnvelopeError,
                .canonicalPayloadDigestMismatch(
                    expected: String(repeating: "c", count: 64),
                    actual: String(repeating: "d", count: 64)
                )
            )
        }
        XCTAssertEqual(harness.publisherVerificationCount, 0)
        XCTAssertTrue(harness.observedArtifactIds.isEmpty)
    }

    func testPreservesUnavailablePublisherKeyAsUnavailable() {
        let harness = VerificationHarness()
        harness.publisherResult = .keyUnavailable(keyId: "helper-release-key-2026")

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapEnvelopeError,
                .publisherKeyUnavailable(keyId: "helper-release-key-2026")
            )
        }
        XCTAssertTrue(harness.observedArtifactIds.isEmpty)
    }

    func testPreservesUnavailableArtifactWithoutConvertingItToMismatch() {
        let harness = VerificationHarness()
        harness.artifactResults["helper-next-updater"] = .unavailable(
            reason: "artifact is missing"
        )

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapEnvelopeError,
                .artifactUnavailable(
                    artifactId: "helper-next-updater",
                    reason: "artifact is missing"
                )
            )
        }
    }

    func testRejectsArtifactDigestMismatch() {
        let harness = VerificationHarness()
        harness.artifactResults["helper-update-specification"] = .available(
            sha256: String(repeating: "f", count: 64),
            sizeBytes: 200
        )

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapEnvelopeError,
                .artifactDigestMismatch(
                    artifactId: "helper-update-specification",
                    expected: String(repeating: "b", count: 64),
                    actual: String(repeating: "f", count: 64)
                )
            )
        }
    }
}

private final class VerificationHarness {
    let envelope = UpdateBootstrapEnvelope(
        schemaVersion: "v1",
        id: "helper-update-0.2.2",
        productId: "ai.tirosh.vitalserver.helper",
        target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
        targetRelease: UpdateBootstrapRelease(
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2"
        ),
        layerOrder: [.container, .guestRuntime, .hostPlatform],
        nextUpdaterArtifact: UpdateBootstrapArtifact(
            id: "helper-next-updater",
            relativePath: "payload/bin/vitalserver-update",
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 100,
            mediaType: "application/octet-stream"
        ),
        specification: UpdateBootstrapArtifact(
            id: "helper-update-specification",
            relativePath: "payload/update-specification.json",
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 200,
            mediaType: "application/json"
        ),
        signature: UpdateBootstrapSignature(
            algorithm: .ed25519,
            keyId: "helper-release-key-2026",
            signedSha256: String(repeating: "c", count: 64),
            value: "signature"
        ),
        issuedAt: "2026-07-27T00:00:00Z"
    )
    var canonicalPayloadSHA256 = String(repeating: "c", count: 64)
    var publisherResult: UpdateBootstrapPublisherVerificationResult = .verified
    var artifactResults: [String: UpdateBootstrapArtifactObservation] = [
        "helper-next-updater": .available(
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 100
        ),
        "helper-update-specification": .available(
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 200
        ),
    ]
    var publisherVerificationCount = 0
    var observedArtifactIds: [String] = []

    func verify() throws -> VerifiedUpdateBootstrapClosure {
        try VerifyUpdateBootstrapEnvelopeUseCase().verify(
            input: VerifyUpdateBootstrapEnvelopeInput(
                envelope: envelope,
                expectedProductId: "ai.tirosh.vitalserver.helper",
                expectedTarget: UpdateBootstrapTarget(
                    platform: .macos,
                    architecture: .arm64
                )
            ),
            operations: VerifyUpdateBootstrapEnvelopeOperations(
                canonicalSignedPayload: { _ in Data("canonical".utf8) },
                sha256: { [self] _ in canonicalPayloadSHA256 },
                verifyPublisherSignature: { [self] _, _, _, _ in
                    publisherVerificationCount += 1
                    return publisherResult
                },
                observeArtifact: { [self] artifact in
                    observedArtifactIds.append(artifact.id)
                    return artifactResults[artifact.id] ?? .failed(
                        reason: "test did not declare artifact observation"
                    )
                }
            )
        )
    }
}
