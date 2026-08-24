import Application
import Contracts
import Domain
import XCTest

final class SettleUpdateBootstrapHandoffUseCaseTests: XCTestCase {
    func testMissingReceiptDoesNotBecomeSuccessOrFailure() throws {
        XCTAssertThrowsError(try SettleUpdateBootstrapHandoffUseCase().execute(
            journal: try runningJournal(),
            receiptRead: .missing(path: "/updates/update-42/receipt.json")
        )) { error in
            XCTAssertEqual(
                error as? SettleUpdateBootstrapHandoffError,
                .receiptMissing(path: "/updates/update-42/receipt.json")
            )
        }
    }

    func testCorrelatedReceiptSettlesJournal() throws {
        let running = try runningJournal()
        let settled = try SettleUpdateBootstrapHandoffUseCase().execute(
            journal: running,
            receiptRead: .loaded(receipt(revision: running.journalRevision))
        )

        XCTAssertEqual(settled.state, .succeeded)
        XCTAssertEqual(settled.completion?.reportRelativePath, "handoff/report.json")
    }

    private func runningJournal() throws -> UpdateBootstrapJournal {
        let admitted = UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: "update-42",
            journalRevision: 1,
            operationId: "operation-42",
            targetInstallationId: "installation-1",
            expectedInstallationRevision: 1,
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
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
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

    private func receipt(revision: Int) -> UpdateBootstrapCompletionReceipt {
        UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: "update-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            expectedJournalRevision: revision,
            outcome: .succeeded,
            reportRelativePath: "handoff/report.json",
            reportSHA256: String(repeating: "c", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T06:10:00Z"
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v2",
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
            payloadArtifacts: [],
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
