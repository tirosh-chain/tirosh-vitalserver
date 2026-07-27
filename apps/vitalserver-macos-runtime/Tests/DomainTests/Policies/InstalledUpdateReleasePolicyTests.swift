import Contracts
import Domain
import XCTest

final class InstalledUpdateReleasePolicyTests: XCTestCase {
    func testMakesInstalledReleaseOnlyFromSucceededCorrelatedJournal() throws {
        let journal = try succeededJournal()

        let release = try InstalledUpdateReleasePolicy.make(from: journal)

        XCTAssertEqual(release.productId, "ai.tirosh.vitalserver.helper")
        XCTAssertEqual(release.productVersion, "0.2.2")
        XCTAssertEqual(release.runtimeVersion, "0.2.2")
        XCTAssertEqual(release.updateId, journal.id)
        XCTAssertEqual(release.journalRevision, journal.journalRevision)
        XCTAssertEqual(release.reportSHA256, String(repeating: "d", count: 64))
        XCTAssertEqual(release.settledAt, "2026-07-27T01:00:00Z")
    }

    func testRejectsReleaseThatDoesNotMatchSucceededJournal() throws {
        let journal = try succeededJournal()
        let release = try InstalledUpdateReleasePolicy.make(from: journal)
        let mismatched = InstalledUpdateRelease(
            schemaVersion: release.schemaVersion,
            productId: release.productId,
            productVersion: "9.9.9",
            runtimeVersion: release.runtimeVersion,
            updateId: release.updateId,
            journalId: release.journalId,
            journalRevision: release.journalRevision,
            reportRelativePath: release.reportRelativePath,
            reportSHA256: release.reportSHA256,
            settledAt: release.settledAt
        )

        XCTAssertThrowsError(
            try InstalledUpdateReleasePolicy.validate(
                mismatched,
                against: journal
            )
        ) { error in
            XCTAssertEqual(
                error as? InstalledUpdateReleaseValidationError,
                .journalMismatch(
                    field: "productVersion",
                    expected: "0.2.2",
                    actual: "9.9.9"
                )
            )
        }
    }

    func testRejectsNonSucceededJournal() {
        XCTAssertThrowsError(
            try InstalledUpdateReleasePolicy.make(from: admittedJournal())
        ) { error in
            XCTAssertEqual(
                error as? InstalledUpdateReleaseValidationError,
                .journalIsNotSucceeded(.admitted)
            )
        }
    }

    func testRejectsNonCanonicalSettlementTimestamp() throws {
        let release = try InstalledUpdateReleasePolicy.make(
            from: succeededJournal()
        )
        let invalid = InstalledUpdateRelease(
            schemaVersion: release.schemaVersion,
            productId: release.productId,
            productVersion: release.productVersion,
            runtimeVersion: release.runtimeVersion,
            updateId: release.updateId,
            journalId: release.journalId,
            journalRevision: release.journalRevision,
            reportRelativePath: release.reportRelativePath,
            reportSHA256: release.reportSHA256,
            settledAt: "2026-07-27 01:00:00"
        )

        XCTAssertThrowsError(
            try InstalledUpdateReleasePolicy.validate(invalid)
        ) { error in
            XCTAssertEqual(
                error as? InstalledUpdateReleaseValidationError,
                .invalidField(
                    field: "settledAt",
                    value: "2026-07-27 01:00:00"
                )
            )
        }
    }

    private func succeededJournal() throws -> UpdateBootstrapJournal {
        let admitted = admittedJournal()
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .verifiedAndStaged(
                updaterRelativePath: "payload/bin/vitalserver-update",
                specificationRelativePath: "payload/update-specification.json",
                observedAt: "2026-07-27T00:10:00Z"
            )
        )
        let running = try UpdateBootstrapJournalStateMachine.transition(
            journal: pending,
            event: .handoffStarted(observedAt: "2026-07-27T00:20:00Z")
        )
        return try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .completed(receipt())
        )
    }

    private func admittedJournal() -> UpdateBootstrapJournal {
        UpdateBootstrapJournal(
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
    }

    private func receipt() -> UpdateBootstrapCompletionReceipt {
        UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: "update-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            expectedJournalRevision: 3,
            outcome: .succeeded,
            reportRelativePath: "handoff/report.json",
            reportSHA256: String(repeating: "d", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T01:00:00Z"
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v1",
            id: "envelope-42",
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
            nextUpdaterArtifact: artifact(
                id: "next-updater",
                path: "payload/bin/vitalserver-update",
                sha256: String(repeating: "a", count: 64)
            ),
            specification: artifact(
                id: "specification",
                path: "payload/update-specification.json",
                sha256: String(repeating: "b", count: 64)
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

    private func artifact(
        id: String,
        path: String,
        sha256: String
    ) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: path,
            sha256: sha256,
            sizeBytes: 42,
            mediaType: "application/octet-stream"
        )
    }
}
