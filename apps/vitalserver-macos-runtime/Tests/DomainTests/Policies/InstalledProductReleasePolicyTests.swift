import Contracts
import Domain
import XCTest

final class InstalledProductReleasePolicyTests: XCTestCase {
    func testMakesPackageInstallReleaseAsRevisionOne() throws {
        let release = try packageInstallRelease()

        XCTAssertEqual(release.releaseRevision, 1)
        XCTAssertEqual(release.source, .packageInstall)
        XCTAssertEqual(release.installOperationId, "install-42")
        XCTAssertNil(release.updateId)
    }

    func testMakesNextReleaseOnlyFromCurrentReleaseAndSucceededJournal() throws {
        let journal = try succeededJournal()

        let release = try InstalledProductReleasePolicy.makeUpdate(
            current: packageInstallRelease(),
            from: journal
        )

        XCTAssertEqual(release.productVersion, "0.2.3")
        XCTAssertEqual(release.releaseRevision, 2)
        XCTAssertEqual(release.source, .update)
        XCTAssertEqual(release.updateId, journal.id)
        XCTAssertEqual(release.journalRevision, journal.journalRevision)
    }

    func testRejectsUpdateForDifferentProductOwner() throws {
        let current = try InstalledProductReleasePolicy.makePackageInstall(
            productId: "different.product",
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2",
            installOperationId: "install-42",
            settledAt: "2026-07-27T00:00:00Z"
        )

        XCTAssertThrowsError(try InstalledProductReleasePolicy.makeUpdate(
            current: current,
            from: succeededJournal()
        )) { error in
            XCTAssertEqual(
                error as? InstalledProductReleaseValidationError,
                .productMismatch(
                    expected: "different.product",
                    actual: "ai.tirosh.vitalserver.helper"
                )
            )
        }
    }

    func testRejectsPackageInstallWithUpdateEvidence() throws {
        let valid = try packageInstallRelease()
        let invalid = InstalledProductRelease(
            schemaVersion: valid.schemaVersion,
            productId: valid.productId,
            productVersion: valid.productVersion,
            runtimeVersion: valid.runtimeVersion,
            releaseRevision: valid.releaseRevision,
            source: .packageInstall,
            installOperationId: valid.installOperationId,
            updateId: "update-42",
            journalId: nil,
            journalRevision: nil,
            reportRelativePath: nil,
            reportSHA256: nil,
            settledAt: valid.settledAt
        )

        XCTAssertThrowsError(try InstalledProductReleasePolicy.validate(invalid)) {
            XCTAssertEqual(
                $0 as? InstalledProductReleaseValidationError,
                .invalidEvidenceShape(.packageInstall)
            )
        }
    }

    private func packageInstallRelease() throws -> InstalledProductRelease {
        try InstalledProductReleasePolicy.makePackageInstall(
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2",
            installOperationId: "install-42",
            settledAt: "2026-07-27T00:00:00Z"
        )
    }

    private func succeededJournal() throws -> UpdateBootstrapJournal {
        let admitted = UpdateBootstrapJournal(
            schemaVersion: "v1",
            id: "update-42",
            journalRevision: 1,
            operationId: "operation-42",
            requestId: "request-42",
            envelope: envelope(),
            bootstrapSignedSHA256: String(repeating: "c", count: 64),
            state: .admitted,
            stagedUpdaterRelativePath: nil,
            stagedSpecificationRelativePath: nil,
            completion: nil,
            failureReason: nil,
            createdAt: "2026-07-27T00:00:00Z",
            updatedAt: "2026-07-27T00:00:00Z"
        )
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .verifiedAndStaged(
                updaterRelativePath: "payload/next-updater",
                specificationRelativePath: "payload/specification.json",
                observedAt: "2026-07-27T00:10:00Z"
            )
        )
        let running = try UpdateBootstrapJournalStateMachine.transition(
            journal: pending,
            event: .handoffStarted(observedAt: "2026-07-27T00:20:00Z")
        )
        return try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .completed(UpdateBootstrapCompletionReceipt(
                schemaVersion: "v1",
                updateId: admitted.id,
                requestId: admitted.requestId,
                bootstrapEnvelopeId: admitted.envelope.id,
                updateSpecificationSHA256: admitted.envelope.specification.sha256,
                expectedJournalRevision: running.journalRevision,
                outcome: .succeeded,
                reportRelativePath: "handoff/report.json",
                reportSHA256: String(repeating: "d", count: 64),
                failureReason: nil,
                finishedAt: "2026-07-27T01:00:00Z"
            ))
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v1",
            id: "envelope-42",
            productId: "ai.tirosh.vitalserver.helper",
            target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.3",
                runtimeVersion: "0.2.3"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: artifact("next-updater", "payload/next-updater"),
            specification: artifact("specification", "payload/specification.json"),
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: "2026-07-27T00:00:00Z"
        )
    }

    private func artifact(_ id: String, _ path: String) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: path,
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 42,
            mediaType: "application/octet-stream"
        )
    }
}
