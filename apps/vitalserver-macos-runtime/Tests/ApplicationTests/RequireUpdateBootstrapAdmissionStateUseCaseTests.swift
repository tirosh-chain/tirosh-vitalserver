import Application
import Contracts
import XCTest

final class RequireUpdateBootstrapAdmissionStateUseCaseTests: XCTestCase {
    func testReturnsInstalledReleaseOnlyWhenJournalIsExplicitlyMissing() throws {
        let release = admissionInstalledRelease()

        XCTAssertEqual(
            try RequireUpdateBootstrapAdmissionStateUseCase()
                .requireNewAdmission(
                    installedRelease: .loaded(release),
                    journalId: "update-1",
                    journal: .missing
                ),
            release
        )
    }

    func testPreservesMissingAndFailedInstalledRelease() {
        assertError(
            installedRelease: .missing,
            journal: .missing,
            expected: .installedReleaseMissing
        )
        assertError(
            installedRelease: .failed(reason: "database unavailable"),
            journal: .missing,
            expected: .installedReleaseReadFailed(
                reason: "database unavailable"
            )
        )
    }

    func testExistingAndFailedJournalCannotBecomeNewAdmission() {
        let journal = admissionJournal()
        assertError(
            installedRelease: .loaded(admissionInstalledRelease()),
            journal: .loaded(journal),
            expected: .journalAlreadyExists(
                id: journal.id,
                state: journal.state,
                requestId: journal.requestId
            )
        )
        assertError(
            installedRelease: .loaded(admissionInstalledRelease()),
            journal: .failed(reason: "decode failed"),
            expected: .journalReadFailed(
                id: "update-1",
                reason: "decode failed"
            )
        )
    }

    private func assertError(
        installedRelease: InstalledProductReleaseReadResult,
        journal: UpdateBootstrapJournalReadResult,
        expected: RequireUpdateBootstrapAdmissionStateError
    ) {
        XCTAssertThrowsError(
            try RequireUpdateBootstrapAdmissionStateUseCase()
                .requireNewAdmission(
                    installedRelease: installedRelease,
                    journalId: "update-1",
                    journal: journal
                )
        ) { error in
            XCTAssertEqual(
                error as? RequireUpdateBootstrapAdmissionStateError,
                expected
            )
        }
    }
}

private func admissionInstalledRelease() -> InstalledProductRelease {
    InstalledProductRelease(
        schemaVersion: "v1",
        productId: "ai.tirosh.vitalserver.helper",
        productVersion: "0.2.2",
        runtimeVersion: "0.2.2",
        releaseRevision: 1,
        source: .packageInstall,
        installOperationId: "install-1",
        updateId: nil,
        journalId: nil,
        journalRevision: nil,
        reportRelativePath: nil,
        reportSHA256: nil,
        settledAt: "2026-07-27T00:00:00Z"
    )
}

private func admissionJournal() -> UpdateBootstrapJournal {
    UpdateBootstrapJournal(
        schemaVersion: "v1",
        id: "update-1",
        journalRevision: 1,
        operationId: "operation-1",
        requestId: "request-1",
        envelope: UpdateBootstrapEnvelope(
            schemaVersion: "v1",
            id: "update-1",
            productId: "ai.tirosh.vitalserver.helper",
            target: .init(platform: .macos, architecture: .arm64),
            targetRelease: .init(
                productVersion: "0.2.3",
                runtimeVersion: "0.2.3"
            ),
            layerOrder: [.hostPlatform],
            nextUpdaterArtifact: .init(
                id: "updater",
                relativePath: "payload/updater",
                sha256: String(repeating: "a", count: 64),
                sizeBytes: 1,
                mediaType: "application/octet-stream"
            ),
            specification: .init(
                id: "specification",
                relativePath: "payload/specification.json",
                sha256: String(repeating: "b", count: 64),
                sizeBytes: 1,
                mediaType: "application/json"
            ),
            signature: .init(
                algorithm: .ed25519,
                keyId: "release-key",
                signedSha256: String(repeating: "c", count: 64),
                value: "signature"
            ),
            issuedAt: "2026-07-27T01:00:00Z"
        ),
        bootstrapSignedSHA256: String(repeating: "c", count: 64),
        state: .admitted,
        stagedUpdaterRelativePath: nil,
        stagedSpecificationRelativePath: nil,
        completion: nil,
        failureReason: nil,
        createdAt: "2026-07-27T01:00:00Z",
        updatedAt: "2026-07-27T01:00:00Z"
    )
}
