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

    func testPackageInstallRejectsReplacingExistingInstallation() throws {
        let context = try makeContext()
        let replacement = try InstalledProductReleasePolicy
            .makePackageInstall(
                installationId: "installation-2",
                productId: "ai.tirosh.vitalserver.helper",
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2",
                installOperationId: "install-2",
                settledAt: "2026-07-27T00:01:00Z"
            )

        XCTAssertThrowsError(
            try context.repository.settlePackageInstallRelease(replacement)
        ) { error in
            XCTAssertEqual(
                error as? SQLiteUpdateBootstrapJournalRepositoryError,
                .installedReleaseAlreadyExists(
                    installationId: "installation-1",
                    installationRevision: 1
                )
            )
        }
        XCTAssertEqual(
            context.repository.loadInstalledProductRelease(),
            .loaded(try baselineRelease())
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
        let release = try InstalledProductReleasePolicy.makeUpdate(
            current: try baselineRelease(),
            from: succeeded
        )

        try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: release,
            expectedJournalRevision: 3,
            expectedInstallationRevision: 1
        )

        XCTAssertEqual(
            context.repository.loadUpdateBootstrapJournal(id: admitted.id),
            .loaded(succeeded)
        )
        XCTAssertEqual(
            context.repository.loadInstalledProductRelease(),
            .loaded(release)
        )
        XCTAssertEqual(release.installationId, "installation-1")
        XCTAssertEqual(release.installationRevision, 2)
        XCTAssertEqual(release.releaseRevision, 2)
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
        let valid = try InstalledProductReleasePolicy.makeUpdate(
            current: try baselineRelease(),
            from: succeeded
        )
        let invalid = InstalledProductRelease(
            schemaVersion: valid.schemaVersion,
            installationId: valid.installationId,
            installationRevision: valid.installationRevision,
            productId: valid.productId,
            productVersion: "wrong-version",
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

        XCTAssertThrowsError(try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: invalid,
            expectedJournalRevision: 3,
            expectedInstallationRevision: 1
        ))
        guard case .loaded(let unchanged) =
            context.repository.loadUpdateBootstrapJournal(id: admitted.id)
        else {
            return XCTFail("expected running journal")
        }
        XCTAssertEqual(unchanged.state, .running)
        XCTAssertEqual(unchanged.journalRevision, 3)
        XCTAssertEqual(
            context.repository.loadInstalledProductRelease(),
            .loaded(try baselineRelease())
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
        let release = try InstalledProductReleasePolicy.makeUpdate(
            current: try baselineRelease(),
            from: succeeded
        )

        XCTAssertThrowsError(try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: release,
            expectedJournalRevision: 2,
            expectedInstallationRevision: 1
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
            context.repository.loadInstalledProductRelease(),
            .loaded(try baselineRelease())
        )
    }

    func testStaleInstallationRevisionChangesNeitherJournalNorRelease() throws {
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
        let release = try InstalledProductReleasePolicy.makeUpdate(
            current: try baselineRelease(),
            from: succeeded
        )

        XCTAssertThrowsError(try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: release,
            expectedJournalRevision: 3,
            expectedInstallationRevision: 9
        )) { error in
            XCTAssertEqual(
                error as? SQLiteUpdateBootstrapJournalRepositoryError,
                .settlementInstallationRevisionMismatch(
                    journal: 1,
                    caller: 9
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
            context.repository.loadInstalledProductRelease(),
            .loaded(try baselineRelease())
        )
    }

    func testPreReinstallWriterWithDifferentInstallationIdentityChangesNeitherAggregate() throws {
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
        let valid = try InstalledProductReleasePolicy.makeUpdate(
            current: try baselineRelease(),
            from: succeeded
        )
        let differentInstallation = InstalledProductRelease(
            schemaVersion: valid.schemaVersion,
            installationId: "installation-other",
            installationRevision: valid.installationRevision,
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

        XCTAssertThrowsError(try context.repository.settleSucceededUpdate(
            journal: succeeded,
            release: differentInstallation,
            expectedJournalRevision: 3,
            expectedInstallationRevision: 1
        )) { error in
            XCTAssertEqual(
                error as? SQLiteUpdateBootstrapJournalRepositoryError,
                .installedReleaseIdentityMismatch(
                    expected: "installation-other",
                    actual: "installation-1"
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
            context.repository.loadInstalledProductRelease(),
            .loaded(try baselineRelease())
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
        let repository = SQLiteUpdateBootstrapJournalRepository(
            databaseURL: databaseURL,
            validate: ValidateUpdateBootstrapJournalUseCase().validate,
            validateRelease: InstalledProductReleasePolicy.validate,
            validateSettlement: InstalledProductReleasePolicy.validate
        )
        try repository.settlePackageInstallRelease(try baselineRelease())
        try SQLiteRuntimeOperationLeaseRepository(
            databaseURL: databaseURL
        ).acquire(
            RuntimeOperationLeaseDocument(
                operationId: "operation-1",
                operation: .applyUpdateBootstrap,
                targetInstallationId: "installation-1",
                expectedInstallationRevision: 1,
                ownerPID: 123,
                startedAt: "2026-07-27T00:00:00Z",
                heartbeatAt: "2026-07-27T00:00:00Z",
                expiresAt: "2026-07-27T01:00:00Z",
                message: nil
            )
        )
        return (repository, databaseURL)
    }

    private func baselineRelease() throws -> InstalledProductRelease {
        try InstalledProductReleasePolicy.makePackageInstall(
            installationId: "installation-1",
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2",
            installOperationId: "install-1",
            settledAt: "2026-07-27T00:00:00Z"
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
