import Contracts
import Domain
import XCTest

final class UpdateBootstrapHandoffPolicyTests: XCTestCase {
    func testMakesFixedInvocationFromRunningJournal() throws {
        let journal = try runningJournal()

        let invocation = try UpdateBootstrapHandoffPolicy.makeInvocation(
            journal: journal
        )

        XCTAssertEqual(
            invocation.schemaVersion,
            "vitalserver.update-bootstrap-handoff/v1"
        )
        XCTAssertEqual(invocation.updateId, journal.id)
        XCTAssertEqual(invocation.operationId, journal.operationId)
        XCTAssertEqual(invocation.requestId, journal.requestId)
        XCTAssertEqual(invocation.bootstrapEnvelopeId, journal.envelope.id)
        XCTAssertEqual(
            invocation.layerOrder,
            [.container, .guestRuntime, .hostPlatform]
        )
        XCTAssertEqual(invocation.expectedJournalRevision, journal.journalRevision)
        XCTAssertEqual(invocation.updaterRelativePath, "updater/next-updater")
        XCTAssertEqual(invocation.specificationRelativePath, "spec/update.json")
        XCTAssertEqual(
            invocation.completionReceiptRelativePath,
            "handoff/completion-receipt.json"
        )
    }

    func testRejectsHandoffBeforeRunningStateIsPersisted() throws {
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admittedJournal(),
            event: .verifiedAndStaged(
                updaterRelativePath: "updater/next-updater",
                specificationRelativePath: "spec/update.json",
                observedAt: "2026-07-27T06:01:00Z"
            )
        )

        XCTAssertThrowsError(
            try UpdateBootstrapHandoffPolicy.makeInvocation(journal: pending)
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffPolicyError,
                .journalIsNotRunning(.handoffPending)
            )
        }
    }

    private func runningJournal() throws -> UpdateBootstrapJournal {
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admittedJournal(),
            event: .verifiedAndStaged(
                updaterRelativePath: "updater/next-updater",
                specificationRelativePath: "spec/update.json",
                observedAt: "2026-07-27T06:01:00Z"
            )
        )
        return try UpdateBootstrapJournalStateMachine.transition(
            journal: pending,
            event: .handoffStarted(observedAt: "2026-07-27T06:02:00Z")
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
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            state: .admitted,
            stagedUpdaterRelativePath: nil,
            stagedSpecificationRelativePath: nil,
            completion: nil,
            failureReason: nil,
            createdAt: "2026-07-27T06:00:00Z",
            updatedAt: "2026-07-27T06:00:00Z"
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "vitalserver.update-bootstrap/v1",
            id: "envelope-42",
            productId: "com.tirosh.vitalserver-helper",
            target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: artifact(
                id: "next-updater",
                path: "updater/next-updater"
            ),
            specification: artifact(
                id: "update-specification",
                path: "spec/update.json"
            ),
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key-1",
                signedSha256: String(repeating: "a", count: 64),
                value: "c2lnbmF0dXJl"
            ),
            issuedAt: "2026-07-27T06:00:00Z"
        )
    }

    private func artifact(id: String, path: String) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: path,
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 64,
            mediaType: "application/octet-stream"
        )
    }
}
