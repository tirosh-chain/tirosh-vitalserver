import Contracts
import Domain
import XCTest

final class InstalledProductReleasePolicyTests: XCTestCase {
    func testMakesPackageInstallReleaseAsRevisionOne() throws {
        let release = try packageInstallRelease()

        XCTAssertEqual(release.installationId, "installation-42")
        XCTAssertEqual(release.installationRevision, 1)
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
        XCTAssertEqual(release.installationId, "installation-42")
        XCTAssertEqual(release.installationRevision, 2)
        XCTAssertEqual(release.releaseRevision, 2)
        XCTAssertEqual(release.source, .update)
        XCTAssertEqual(release.updateId, journal.id)
        XCTAssertEqual(release.journalRevision, journal.journalRevision)
    }

    func testRejectsUpdateForDifferentProductOwner() throws {
        let current = try InstalledProductReleasePolicy.makePackageInstall(
            installationId: "installation-42",
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
            installationId: valid.installationId,
            installationRevision: valid.installationRevision,
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

    func testRejectsInstallationRevisionBehindReleaseRevision() throws {
        let valid = try InstalledProductReleasePolicy.makeUpdate(
            current: packageInstallRelease(),
            from: succeededJournal()
        )
        let invalid = InstalledProductRelease(
            schemaVersion: valid.schemaVersion,
            installationId: valid.installationId,
            installationRevision: 1,
            productId: valid.productId,
            productVersion: valid.productVersion,
            runtimeVersion: valid.runtimeVersion,
            releaseRevision: valid.releaseRevision,
            source: valid.source,
            installOperationId: valid.installOperationId,
            updateId: valid.updateId,
            journalId: valid.journalId,
            journalRevision: valid.journalRevision,
            reportRelativePath: valid.reportRelativePath,
            reportSHA256: valid.reportSHA256,
            settledAt: valid.settledAt
        )

        XCTAssertThrowsError(
            try InstalledProductReleasePolicy.validate(invalid)
        ) {
            XCTAssertEqual(
                $0 as? InstalledProductReleaseValidationError,
                .invalidInstallationRevision(1)
            )
        }
    }

    private func packageInstallRelease() throws -> InstalledProductRelease {
        try InstalledProductReleasePolicy.makePackageInstall(
            installationId: "installation-42",
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2",
            installOperationId: "install-42",
            settledAt: "2026-07-27T00:00:00Z"
        )
    }

    private func succeededJournal() throws -> UpdateBootstrapJournal {
        let admitted = UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: "update-42",
            journalRevision: 1,
            operationId: "operation-42",
            targetInstallationId: "installation-42",
            expectedInstallationRevision: 1,
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
            schemaVersion: "v2",
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
            payloadArtifacts: [],
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
