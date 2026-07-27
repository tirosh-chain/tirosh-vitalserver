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
            SQLiteUpdateBootstrapJournalRepository(databaseURL: databaseURL),
            databaseURL
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
