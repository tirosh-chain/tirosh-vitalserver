import Application
import Contracts
import XCTest

final class RequireUpdateBootstrapRecoveryStateUseCaseTests: XCTestCase {
    func testRequiresPendingJournalForResume() throws {
        let journal = recoveryJournal(state: .handoffPending)

        XCTAssertEqual(
            try RequireUpdateBootstrapRecoveryStateUseCase().requireJournal(
                id: journal.id,
                action: .resumeHandoff,
                journalRead: .loaded(journal)
            ),
            journal
        )
    }

    func testRequiresRunningJournalForSettlement() throws {
        let journal = recoveryJournal(state: .running)

        XCTAssertEqual(
            try RequireUpdateBootstrapRecoveryStateUseCase().requireJournal(
                id: journal.id,
                action: .settleHandoff,
                journalRead: .loaded(journal)
            ),
            journal
        )
    }

    func testMissingJournalRemainsDistinct() {
        XCTAssertThrowsError(
            try RequireUpdateBootstrapRecoveryStateUseCase().requireJournal(
                id: "update-42",
                action: .resumeHandoff,
                journalRead: .missing
            )
        ) { error in
            XCTAssertEqual(
                error as? RequireUpdateBootstrapRecoveryStateError,
                .journalMissing(id: "update-42")
            )
        }
    }

    func testReadFailureRemainsDistinct() {
        XCTAssertThrowsError(
            try RequireUpdateBootstrapRecoveryStateUseCase().requireJournal(
                id: "update-42",
                action: .settleHandoff,
                journalRead: .failed(reason: "sqlite denied")
            )
        ) { error in
            XCTAssertEqual(
                error as? RequireUpdateBootstrapRecoveryStateError,
                .journalReadFailed(
                    id: "update-42",
                    reason: "sqlite denied"
                )
            )
        }
    }

    func testDoesNotTreatRunningJournalAsSafeToResume() {
        XCTAssertThrowsError(
            try RequireUpdateBootstrapRecoveryStateUseCase().requireJournal(
                id: "update-42",
                action: .resumeHandoff,
                journalRead: .loaded(
                    recoveryJournal(state: .running)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RequireUpdateBootstrapRecoveryStateError,
                .invalidState(
                    id: "update-42",
                    action: .resumeHandoff,
                    expected: [.handoffPending],
                    actual: .running
                )
            )
        }
    }

    func testExplicitFailureAcceptsAnyNonTerminalJournal() throws {
        for state in [
            UpdateBootstrapJournalState.admitted,
            .handoffPending,
            .running,
        ] {
            let journal = recoveryJournal(state: state)
            XCTAssertEqual(
                try RequireUpdateBootstrapRecoveryStateUseCase()
                    .requireJournal(
                        id: journal.id,
                        action: .failNonTerminal,
                        journalRead: .loaded(journal)
                    ),
                journal
            )
        }
    }

    func testExplicitFailureRejectsTerminalJournal() {
        let journal = UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: "update-42",
            journalRevision: 4,
            operationId: "operation-42",
            targetInstallationId: "installation-1",
            expectedInstallationRevision: 1,
            requestId: "request-42",
            envelope: recoveryJournal(state: .running).envelope,
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            state: .failed,
            stagedUpdaterRelativePath:
                "payload/bin/vitalserver-update",
            stagedSpecificationRelativePath:
                "payload/update-specification.json",
            completion: nil,
            failureReason: "already failed",
            createdAt: "2026-07-27T00:00:00Z",
            updatedAt: "2026-07-27T00:02:00Z"
        )

        XCTAssertThrowsError(
            try RequireUpdateBootstrapRecoveryStateUseCase().requireJournal(
                id: journal.id,
                action: .failNonTerminal,
                journalRead: .loaded(journal)
            )
        ) { error in
            XCTAssertEqual(
                error as? RequireUpdateBootstrapRecoveryStateError,
                .invalidState(
                    id: journal.id,
                    action: .failNonTerminal,
                    expected: [.admitted, .handoffPending, .running],
                    actual: .failed
                )
            )
        }
    }
}

func recoveryJournal(
    state: UpdateBootstrapJournalState
) -> UpdateBootstrapJournal {
    let hasStaging = state != .admitted
    return UpdateBootstrapJournal(
        schemaVersion: "v2",
        id: "update-42",
        journalRevision: state == .handoffPending ? 2 : 3,
        operationId: "operation-42",
        targetInstallationId: "installation-1",
        expectedInstallationRevision: 1,
        requestId: "request-42",
        envelope: recoveryEnvelope(),
        bootstrapSignedSHA256: String(repeating: "a", count: 64),
        state: state,
        stagedUpdaterRelativePath:
            hasStaging ? "payload/bin/vitalserver-update" : nil,
        stagedSpecificationRelativePath:
            hasStaging ? "payload/update-specification.json" : nil,
        completion: nil,
        failureReason: nil,
        createdAt: "2026-07-27T00:00:00Z",
        updatedAt: "2026-07-27T00:01:00Z"
    )
}

private func recoveryEnvelope() -> UpdateBootstrapEnvelope {
    UpdateBootstrapEnvelope(
        schemaVersion: "v1",
        id: "update-42",
        productId: "com.tirosh.vitalserver-helper",
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
            relativePath: "payload/bin/vitalserver-update",
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 10,
            mediaType: "application/octet-stream"
        ),
        specification: UpdateBootstrapArtifact(
            id: "update-specification",
            relativePath: "payload/update-specification.json",
            sha256: String(repeating: "c", count: 64),
            sizeBytes: 20,
            mediaType: "application/json"
        ),
        signature: UpdateBootstrapSignature(
            algorithm: .ed25519,
            keyId: "key-1",
            signedSha256: String(repeating: "a", count: 64),
            value: "signature"
        ),
        issuedAt: "2026-07-27T00:00:00Z"
    )
}
