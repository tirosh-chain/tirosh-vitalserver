import Application
import Contracts
import Domain
import XCTest

final class VerifyUpdateBootstrapPayloadClosureUseCaseTests: XCTestCase {
    func testVerifiesExactEnvelopeOwnedPayloadAfterEnvelopeVerification() throws {
        let harness = PayloadClosureHarness()

        let verified = try harness.verify()

        XCTAssertEqual(
            verified.verifiedBootstrapArtifactIds
                + verified.verifiedPayloadArtifactIds,
            [
                "next-updater",
                "specification",
                "host-artifact",
                "host-executor",
                "host-configuration",
                "host-rollback",
            ]
        )
        XCTAssertEqual(
            harness.observedArtifactIds,
            [
                "host-artifact",
                "host-executor",
                "host-configuration",
                "host-rollback",
            ]
        )
    }

    func testRejectsUnknownFileBeforeObservingPayloadArtifacts() {
        let harness = PayloadClosureHarness()
        harness.entries.append(
            .init(relativePath: "payload/unknown", kind: .regularFile)
        )

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapPayloadClosureError,
                .closureInvalid(
                    .fileClosureMismatch(
                        missing: [],
                        unknown: ["payload/unknown"]
                    )
                )
            )
        }
        XCTAssertTrue(harness.observedArtifactIds.isEmpty)
    }

    func testPreservesPayloadDigestMismatch() {
        let harness = PayloadClosureHarness()
        harness.observations["host-artifact"] = .available(
            sha256: String(repeating: "f", count: 64),
            sizeBytes: 10
        )

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapPayloadClosureError,
                .artifactDigestMismatch(
                    artifactId: "host-artifact",
                    expected: String(repeating: "a", count: 64),
                    actual: String(repeating: "f", count: 64)
                )
            )
        }
    }

    func testRejectsMissingPayloadArtifact() {
        let harness = PayloadClosureHarness()
        harness.entries = harness.entries.filter {
            $0.relativePath != "payload/layers/host-platform/artifact"
        }

        XCTAssertThrowsError(try harness.verify()) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapPayloadClosureError,
                .closureInvalid(
                    .fileClosureMismatch(
                        missing: ["payload/layers/host-platform/artifact"],
                        unknown: []
                    )
                )
            )
        }
    }
}

private final class PayloadClosureHarness {
    let envelope = payloadEnvelope()
    let envelopeVerification = VerifiedUpdateBootstrapClosure(
        updateId: "update-0.2.2",
        canonicalPayloadSHA256: String(repeating: "c", count: 64),
        verifiedBootstrapArtifactIds: ["next-updater", "specification"],
        verifiedPayloadArtifactIds: []
    )
    var entries: [UpdateBootstrapBundleEntry]
    var observations: [String: UpdateBootstrapArtifactObservation]
    var observedArtifactIds: [String] = []

    init() {
        let artifacts = payloadEnvelope().payloadArtifacts
        entries = [
            .init(
                relativePath: "bootstrap-envelope.json",
                kind: .regularFile
            ),
            .init(
                relativePath: "payload/bin/vitalserver-update",
                kind: .regularFile
            ),
            .init(
                relativePath: "payload/update-specification.json",
                kind: .regularFile
            ),
        ] + artifacts.map {
            .init(relativePath: $0.relativePath, kind: .regularFile)
        }
        observations = Dictionary(
            uniqueKeysWithValues: artifacts.map {
                (
                    $0.id,
                    .available(
                        sha256: $0.sha256,
                        sizeBytes: $0.sizeBytes
                    )
                )
            }
        )
    }

    func verify() throws -> VerifiedUpdateBootstrapClosure {
        try VerifyUpdateBootstrapPayloadClosureUseCase().verify(
            envelope: envelope,
            envelopeVerification: envelopeVerification,
            entries: entries,
            observeArtifact: { [self] artifact in
                observedArtifactIds.append(artifact.id)
                return observations[artifact.id] ?? .failed(
                    reason: "observation was not declared"
                )
            }
        )
    }
}

private func payloadEnvelope() -> UpdateBootstrapEnvelope {
    let root = "payload/layers/host-platform"
    return UpdateBootstrapEnvelope(
        schemaVersion: "v2",
        id: "update-0.2.2",
        productId: "ai.tirosh.vitalserver.helper",
        target: .init(platform: .macos, architecture: .arm64),
        targetRelease: .init(
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2"
        ),
        layerOrder: [.hostPlatform],
        nextUpdaterArtifact: payloadArtifact(
            "next-updater",
            "payload/bin/vitalserver-update",
            "d"
        ),
        specification: payloadArtifact(
            "specification",
            "payload/update-specification.json",
            "e"
        ),
        payloadArtifacts: [
            payloadArtifact("host-artifact", "\(root)/artifact", "a"),
            payloadArtifact("host-executor", "\(root)/effect-executor", "b"),
            payloadArtifact(
                "host-configuration",
                "\(root)/effect-configuration.json",
                "c"
            ),
            payloadArtifact("host-rollback", "\(root)/rollback-artifact", "d"),
        ],
        signature: .init(
            algorithm: .ed25519,
            keyId: "release-key",
            signedSha256: String(repeating: "c", count: 64),
            value: "signature"
        ),
        issuedAt: "2026-07-30T00:00:00Z"
    )
}

private func payloadArtifact(
    _ id: String,
    _ relativePath: String,
    _ digestCharacter: Character
) -> UpdateBootstrapArtifact {
    UpdateBootstrapArtifact(
        id: id,
        relativePath: relativePath,
        sha256: String(repeating: digestCharacter, count: 64),
        sizeBytes: 10,
        mediaType: "application/octet-stream"
    )
}
