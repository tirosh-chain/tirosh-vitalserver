import Contracts
import Domain
import XCTest

final class UpdateBootstrapAdmissionPolicyTests: XCTestCase {
    func testCreatesRevisionOneAdmittedJournalFromVerifiedClosure() throws {
        let envelope = makeEnvelope()
        let journal = try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: verification(for: envelope),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z"
        )

        XCTAssertEqual(journal.id, envelope.id)
        XCTAssertEqual(journal.journalRevision, 1)
        XCTAssertEqual(journal.operationId, "operation-42")
        XCTAssertEqual(journal.targetInstallationId, "installation-42")
        XCTAssertEqual(journal.expectedInstallationRevision, 7)
        XCTAssertEqual(journal.requestId, "request-42")
        XCTAssertEqual(journal.state, .admitted)
        XCTAssertEqual(
            journal.bootstrapSignedSHA256,
            envelope.signature.signedSha256
        )
        XCTAssertNil(journal.stagedUpdaterRelativePath)
        XCTAssertNil(journal.completion)
        XCTAssertNil(journal.platformAgentSelectionCorrelation)
    }

    func testPersistsPlatformAgentSelectionCorrelationWhenIdentitiesMatch() throws {
        let envelope = makeEnvelope()
        let correlation = UpdateBootstrapPlatformAgentSelectionCorrelation(
            selectionId: "11111111-2222-3333-4444-555555555555",
            verificationInvocationId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            updateId: envelope.id,
            canonicalPayloadSHA256: envelope.signature.signedSha256
        )

        let journal = try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: verification(for: envelope),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z",
            platformAgentSelectionCorrelation: correlation
        )

        XCTAssertEqual(journal.platformAgentSelectionCorrelation, correlation)
    }

    func testRejectsPlatformAgentSelectionDigestMismatchAsApplyMismatch() {
        let envelope = makeEnvelope()
        let other = String(repeating: "ab", count: 32)

        XCTAssertThrowsError(try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: verification(for: envelope),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z",
            platformAgentSelectionCorrelation:
                UpdateBootstrapPlatformAgentSelectionCorrelation(
                    selectionId: "11111111-2222-3333-4444-555555555555",
                    verificationInvocationId:
                        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    updateId: envelope.id,
                    canonicalPayloadSHA256: other
                )
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapAdmissionError,
                .platformAgentSelectionDigestMismatch(
                    expected: envelope.signature.signedSha256,
                    actual: other
                )
            )
        }
    }

    func testRejectsVerificationForDifferentEnvelope() {
        let envelope = makeEnvelope()

        XCTAssertThrowsError(try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: VerifiedUpdateBootstrapClosure(
                updateId: "different-update",
                canonicalPayloadSHA256: envelope.signature.signedSha256,
                verifiedBootstrapArtifactIds: [
                    envelope.nextUpdaterArtifact.id,
                    envelope.specification.id,
                ],
                verifiedPayloadArtifactIds: []
            ),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z"
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapAdmissionError,
                .verificationUpdateMismatch(
                    expected: envelope.id,
                    actual: "different-update"
                )
            )
        }
    }

    func testRejectsIncompleteVerifiedArtifactClosure() {
        let envelope = makeEnvelope()

        XCTAssertThrowsError(try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: VerifiedUpdateBootstrapClosure(
                updateId: envelope.id,
                canonicalPayloadSHA256: envelope.signature.signedSha256,
                verifiedBootstrapArtifactIds: [
                    envelope.nextUpdaterArtifact.id
                ],
                verifiedPayloadArtifactIds: envelope.payloadArtifacts.map(\.id)
            ),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z"
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapAdmissionError,
                .verifiedArtifactSetMismatch(
                    expected: [
                        envelope.nextUpdaterArtifact.id,
                        envelope.specification.id,
                    ].sorted(),
                    actual: [envelope.nextUpdaterArtifact.id]
                )
            )
        }
    }

    func testRejectsMissingPayloadProof() {
        let envelope = makeEnvelope()

        XCTAssertThrowsError(try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: VerifiedUpdateBootstrapClosure(
                updateId: envelope.id,
                canonicalPayloadSHA256: envelope.signature.signedSha256,
                verifiedBootstrapArtifactIds: [
                    envelope.nextUpdaterArtifact.id,
                    envelope.specification.id,
                ],
                verifiedPayloadArtifactIds: []
            ),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z"
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapAdmissionError,
                .verifiedPayloadArtifactSetMismatch(
                    expected: envelope.payloadArtifacts.map(\.id).sorted(),
                    actual: []
                )
            )
        }
    }

    func testRejectsExtraPayloadProof() {
        let envelope = makeEnvelope()

        XCTAssertThrowsError(try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: VerifiedUpdateBootstrapClosure(
                updateId: envelope.id,
                canonicalPayloadSHA256: envelope.signature.signedSha256,
                verifiedBootstrapArtifactIds: [
                    envelope.nextUpdaterArtifact.id,
                    envelope.specification.id,
                ],
                verifiedPayloadArtifactIds:
                    envelope.payloadArtifacts.map(\.id) + ["extra-artifact"]
            ),
            operationId: "operation-42",
            installedRelease: installedRelease(),
            requestId: "request-42",
            admittedAt: "2026-07-27T08:00:00Z"
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapAdmissionError,
                .verifiedPayloadArtifactSetMismatch(
                    expected: envelope.payloadArtifacts.map(\.id).sorted(),
                    actual:
                        (envelope.payloadArtifacts.map(\.id) + ["extra-artifact"])
                        .sorted()
                )
            )
        }
    }

    private func verification(
        for envelope: UpdateBootstrapEnvelope
    ) -> VerifiedUpdateBootstrapClosure {
        VerifiedUpdateBootstrapClosure(
            updateId: envelope.id,
            canonicalPayloadSHA256: envelope.signature.signedSha256,
            verifiedBootstrapArtifactIds: [
                envelope.nextUpdaterArtifact.id,
                envelope.specification.id,
            ],
            verifiedPayloadArtifactIds: envelope.payloadArtifacts.map(\.id)
        )
    }

    private func installedRelease() -> InstalledProductRelease {
        InstalledProductRelease(
            schemaVersion: "v2",
            installationId: "installation-42",
            installationRevision: 7,
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.1",
            runtimeVersion: "0.2.1",
            releaseRevision: 7,
            source: .update,
            installOperationId: nil,
            updateId: "update-previous",
            journalId: "update-previous",
            journalRevision: 4,
            reportRelativePath: "handoff/report.json",
            reportSHA256: String(repeating: "d", count: 64),
            settledAt: "2026-07-26T07:00:00Z"
        )
    }

    private func makeEnvelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v2",
            id: "update-42",
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
                id: "next-updater",
                relativePath: "payload/next-updater",
                sha256: String(repeating: "a", count: 64),
                sizeBytes: 100,
                mediaType: "application/octet-stream"
            ),
            specification: UpdateBootstrapArtifact(
                id: "update-specification",
                relativePath: "payload/update-specification.json",
                sha256: String(repeating: "b", count: 64),
                sizeBytes: 200,
                mediaType: "application/json"
            ),
            payloadArtifacts: [
                UpdateBootstrapArtifact(
                    id: "host-artifact",
                    relativePath: "payload/layers/host-platform/apply.bin",
                    sha256: String(repeating: "e", count: 64),
                    sizeBytes: 300,
                    mediaType: "application/octet-stream"
                ),
            ],
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "publisher-1",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: "2026-07-27T07:00:00Z"
        )
    }
}
