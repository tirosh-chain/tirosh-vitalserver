import Contracts
import Domain
import XCTest

final class UpdateBootstrapJournalStateMachineTests: XCTestCase {
    func testMovesFromAdmissionThroughHandoffToCorrelatedSuccess() throws {
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admittedJournal(),
            event: .verifiedAndStaged(
                updaterRelativePath: "staged/next-updater",
                specificationRelativePath: "staged/update-specification.json",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )
        let running = try UpdateBootstrapJournalStateMachine.transition(
            journal: pending,
            event: .handoffStarted(observedAt: "2026-07-27T00:02:00Z")
        )
        let succeeded = try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .completed(receipt(journalRevision: running.journalRevision))
        )

        XCTAssertEqual(pending.state, .handoffPending)
        XCTAssertEqual(running.state, .running)
        XCTAssertEqual(succeeded.state, .succeeded)
        XCTAssertEqual(succeeded.journalRevision, 4)
        XCTAssertNotNil(succeeded.completion)
        XCTAssertNil(succeeded.failureReason)
    }

    func testRejectsCompletionFromOldUpdaterRevision() throws {
        let running = try runningJournal()

        XCTAssertThrowsError(try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .completed(receipt(journalRevision: 1))
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapJournalTransitionError,
                .invalidRevision(expected: 3, actual: 1)
            )
        }
    }

    func testRejectsCompletionForAnotherSpecification() throws {
        let running = try runningJournal()
        let different = UpdateBootstrapCompletionReceipt(
            schemaVersion: "v2",
            updateId: running.id,
            requestId: running.requestId,
            bootstrapEnvelopeId: running.envelope.id,
            updateSpecificationSHA256: String(repeating: "f", count: 64),
            expectedJournalRevision: running.journalRevision,
            outcome: .succeeded,
            reportRelativePath: "reports/result.json",
            reportSHA256: String(repeating: "d", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T00:03:00Z"
        )

        XCTAssertThrowsError(try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .completed(different)
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapJournalTransitionError,
                .correlationMismatch(
                    field: "updateSpecificationSHA256",
                    expected: String(repeating: "b", count: 64),
                    actual: String(repeating: "f", count: 64)
                )
            )
        }
    }

    func testFailureRemainsDistinctFromInterruption() throws {
        let admitted = admittedJournal()
        let failed = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .failed(
                reason: "publisher key unavailable",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )
        let running = try runningJournal()
        let interrupted = try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .interrupted(
                reason: "host rebooted during handoff",
                observedAt: "2026-07-27T00:04:00Z"
            )
        )

        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(interrupted.state, .interrupted)
    }

    private func runningJournal() throws -> UpdateBootstrapJournal {
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admittedJournal(),
            event: .verifiedAndStaged(
                updaterRelativePath: "staged/next-updater",
                specificationRelativePath: "staged/update-specification.json",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )
        return try UpdateBootstrapJournalStateMachine.transition(
            journal: pending,
            event: .handoffStarted(observedAt: "2026-07-27T00:02:00Z")
        )
    }

    func testPreservesPlatformAgentSelectionCorrelationAcrossTransitions() throws {
        let admitted = UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: "update-operation-1",
            journalRevision: 1,
            operationId: "operation-1",
            targetInstallationId: "installation-1",
            expectedInstallationRevision: 1,
            requestId: "request-1",
            envelope: envelope(),
            bootstrapSignedSHA256: String(repeating: "c", count: 64),
            state: .admitted,
            stagedUpdaterRelativePath: nil,
            stagedSpecificationRelativePath: nil,
            completion: nil,
            failureReason: nil,
            createdAt: "2026-07-27T00:00:00Z",
            updatedAt: "2026-07-27T00:00:00Z",
            platformAgentSelectionCorrelation:
                UpdateBootstrapPlatformAgentSelectionCorrelation(
                    selectionId: "11111111-2222-3333-4444-555555555555",
                    verificationInvocationId:
                        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    updateId: "update-operation-1",
                    canonicalPayloadSHA256: String(repeating: "c", count: 64)
                )
        )
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .verifiedAndStaged(
                updaterRelativePath: "staged/next-updater",
                specificationRelativePath: "staged/update-specification.json",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )

        XCTAssertEqual(
            pending.platformAgentSelectionCorrelation?.selectionId,
            "11111111-2222-3333-4444-555555555555"
        )
        XCTAssertEqual(
            pending.platformAgentSelectionCorrelation?.verificationInvocationId,
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
    }

    private func admittedJournal() -> UpdateBootstrapJournal {
        UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: "update-operation-1",
            journalRevision: 1,
            operationId: "operation-1",
            targetInstallationId: "installation-1",
            expectedInstallationRevision: 1,
            requestId: "request-1",
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

    private func receipt(journalRevision: Int) -> UpdateBootstrapCompletionReceipt {
        UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: "update-operation-1",
            requestId: "request-1",
            bootstrapEnvelopeId: "helper-update-0.2.2",
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            expectedJournalRevision: journalRevision,
            outcome: .succeeded,
            reportRelativePath: "reports/result.json",
            reportSHA256: String(repeating: "d", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T00:03:00Z"
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v2",
            id: "helper-update-0.2.2",
            productId: "ai.tirosh.vitalserver.helper",
            target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: artifact(
                id: "next-updater",
                path: "payload/next-updater",
                sha256: String(repeating: "a", count: 64)
            ),
            specification: artifact(
                id: "specification",
                path: "payload/update-specification.json",
                sha256: String(repeating: "b", count: 64)
            ),
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
