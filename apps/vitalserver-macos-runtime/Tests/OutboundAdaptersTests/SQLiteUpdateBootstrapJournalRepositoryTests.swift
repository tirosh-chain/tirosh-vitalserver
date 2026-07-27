import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import XCTest

final class SQLiteUpdateBootstrapJournalRepositoryTests: XCTestCase {
    func testPersistsJournalAndRequiresExpectedRevisionForTransition() throws {
        let context = try makeContext()
        let admitted = journal()

        try context.repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .verifiedAndStaged(
                updaterRelativePath: "staged/next-updater",
                specificationRelativePath: "staged/update-specification.json",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )
        try context.repository.saveUpdateBootstrapJournal(
            pending,
            expectedRevision: 1
        )

        XCTAssertEqual(
            context.repository.loadUpdateBootstrapJournal(id: admitted.id),
            .loaded(pending)
        )
        XCTAssertEqual(
            context.repository.loadLatestUpdateBootstrapJournal(),
            .loaded(pending)
        )
    }

    func testRejectsStaleWriterWithoutChangingJournal() throws {
        let context = try makeContext()
        let admitted = journal()
        try context.repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .verifiedAndStaged(
                updaterRelativePath: "staged/next-updater",
                specificationRelativePath: "staged/update-specification.json",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )

        XCTAssertThrowsError(try context.repository.saveUpdateBootstrapJournal(
            pending,
            expectedRevision: 9
        )) { error in
            XCTAssertEqual(
                error as? SQLiteUpdateBootstrapJournalRepositoryError,
                .staleRevision(
                    id: admitted.id,
                    expected: 9,
                    actual: 1
                )
            )
        }
        XCTAssertEqual(
            context.repository.loadUpdateBootstrapJournal(id: admitted.id),
            .loaded(admitted)
        )
    }

    func testAtomicallySettlesSucceededJournalAndInstalledRelease() throws {
        let context = try makeContext()
        let admitted = journal()
        try context.repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        let succeeded = try prepareSucceededJournal(
            from: admitted,
            repository: context.repository
        )
        let release = try InstalledUpdateReleasePolicy.make(from: succeeded)

        try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: release,
            expectedJournalRevision: 3
        )

        XCTAssertEqual(
            context.repository.loadUpdateBootstrapJournal(id: admitted.id),
            .loaded(succeeded)
        )
        XCTAssertEqual(
            context.repository.loadInstalledUpdateRelease(),
            .loaded(release)
        )
    }

    func testInvalidReleaseDoesNotAdvanceJournal() throws {
        let context = try makeContext()
        let admitted = journal()
        try context.repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        let succeeded = try prepareSucceededJournal(
            from: admitted,
            repository: context.repository
        )
        let valid = try InstalledUpdateReleasePolicy.make(from: succeeded)
        let invalid = InstalledUpdateRelease(
            schemaVersion: valid.schemaVersion,
            productId: valid.productId,
            productVersion: "wrong-version",
            runtimeVersion: valid.runtimeVersion,
            updateId: valid.updateId,
            journalId: valid.journalId,
            journalRevision: valid.journalRevision,
            reportRelativePath: valid.reportRelativePath,
            reportSHA256: valid.reportSHA256,
            settledAt: valid.settledAt
        )

        XCTAssertThrowsError(try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: invalid,
            expectedJournalRevision: 3
        ))
        guard case .loaded(let unchanged) =
            context.repository.loadUpdateBootstrapJournal(id: admitted.id)
        else {
            return XCTFail("expected running journal")
        }
        XCTAssertEqual(unchanged.state, .running)
        XCTAssertEqual(unchanged.journalRevision, 3)
        XCTAssertEqual(
            context.repository.loadInstalledUpdateRelease(),
            .missing
        )
    }

    func testStaleSettlementChangesNeitherJournalNorInstalledRelease() throws {
        let context = try makeContext()
        let admitted = journal()
        try context.repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        let succeeded = try prepareSucceededJournal(
            from: admitted,
            repository: context.repository
        )
        let release = try InstalledUpdateReleasePolicy.make(from: succeeded)

        XCTAssertThrowsError(try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: release,
            expectedJournalRevision: 2
        )) { error in
            XCTAssertEqual(
                error as? SQLiteUpdateBootstrapJournalRepositoryError,
                .staleRevision(
                    id: admitted.id,
                    expected: 2,
                    actual: 3
                )
            )
        }
        guard case .loaded(let unchanged) =
            context.repository.loadUpdateBootstrapJournal(id: admitted.id)
        else {
            return XCTFail("expected running journal")
        }
        XCTAssertEqual(unchanged.state, .running)
        XCTAssertEqual(unchanged.journalRevision, 3)
        XCTAssertEqual(
            context.repository.loadInstalledUpdateRelease(),
            .missing
        )
    }

    private func makeContext() throws -> (
        repository: SQLiteUpdateBootstrapJournalRepository,
        databaseURL: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        return (
            SQLiteUpdateBootstrapJournalRepository(
                databaseURL: databaseURL,
                validate: ValidateUpdateBootstrapJournalUseCase().validate,
                validateRelease: InstalledUpdateReleasePolicy.validate,
                validateSettlement: InstalledUpdateReleasePolicy.validate
            ),
            databaseURL
        )
    }

    private func prepareSucceededJournal(
        from admitted: UpdateBootstrapJournal,
        repository: SQLiteUpdateBootstrapJournalRepository
    ) throws -> UpdateBootstrapJournal {
        let pending = try UpdateBootstrapJournalStateMachine.transition(
            journal: admitted,
            event: .verifiedAndStaged(
                updaterRelativePath: "payload/next-updater",
                specificationRelativePath: "payload/update-specification.json",
                observedAt: "2026-07-27T00:01:00Z"
            )
        )
        let running = try UpdateBootstrapJournalStateMachine.transition(
            journal: pending,
            event: .handoffStarted(observedAt: "2026-07-27T00:02:00Z")
        )
        try repository.saveUpdateBootstrapJournal(
            pending,
            expectedRevision: admitted.journalRevision
        )
        try repository.saveUpdateBootstrapJournal(
            running,
            expectedRevision: pending.journalRevision
        )
        return try UpdateBootstrapJournalStateMachine.transition(
            journal: running,
            event: .completed(
                UpdateBootstrapCompletionReceipt(
                    schemaVersion: "v1",
                    updateId: admitted.id,
                    requestId: admitted.requestId,
                    bootstrapEnvelopeId: admitted.envelope.id,
                    updateSpecificationSHA256:
                        admitted.envelope.specification.sha256,
                    expectedJournalRevision: running.journalRevision,
                    outcome: .succeeded,
                    reportRelativePath: "handoff/report.json",
                    reportSHA256: String(repeating: "d", count: 64),
                    failureReason: nil,
                    finishedAt: "2026-07-27T00:03:00Z"
                )
            )
        )
    }

    private func journal() -> UpdateBootstrapJournal {
        UpdateBootstrapJournal(
            schemaVersion: "v1",
            id: "update-operation-1",
            journalRevision: 1,
            operationId: "operation-1",
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

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v1",
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
