import Application
import Bootstrap
import Contracts
import CryptoKit
import Darwin
import Domain
import Foundation
import InboundAdapters
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeUpdateBootstrapCompositionTests: XCTestCase {
    func testVerifyPersistsReceiptBoundToInstalledHomeAndProcessIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        let bundle = root.appendingPathComponent("incoming-update")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: installed.updateBootstrapTrustStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(bundle, privateKey: privateKey)

        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock()
        )
        try lifecycle.verifyUpdateBootstrap(bundle)

        let receiptURL = installed.updateBootstrapVerificationReceipt(
            updateId: "update-0.2.2"
        )
        let receipt = try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(
            receipt.command,
            UpdateBootstrapVerificationReceiptContract.command
        )
        XCTAssertEqual(receipt.updateId, "update-0.2.2")
        XCTAssertEqual(receipt.resolvedRuntimeHome, installed.runtimeHome.path)
        XCTAssertEqual(
            receipt.trustStorePath,
            installed.updateBootstrapTrustStore.path
        )
        XCTAssertEqual(receipt.uid, getuid())
        XCTAssertEqual(receipt.euid, geteuid())
        XCTAssertEqual(receipt.observedAt, "2026-07-27T00:00:00Z")
        XCTAssertTrue(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                receipt.observedAt
            )
        )
        XCTAssertNotEqual(receipt.resolvedRuntimeHome, "/var/root/.tirosh/vitalserver-vm")
        XCTAssertNil(receipt.verificationInvocationId)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installed.updateBootstrapStagingDirectory
                    .appendingPathComponent("update-0.2.2").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installed.updateBootstrapVerificationInvocationBinding(
                    verificationInvocationId:
                        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
                ).path
            )
        )
    }

    func testVerifyBindsExplicitInvocationIdWithoutInventingOne() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        let bundle = root.appendingPathComponent("incoming-update")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: installed.updateBootstrapTrustStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(bundle, privateKey: privateKey)

        let invocationId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock()
        )
        try lifecycle.verifyUpdateBootstrap(
            RuntimeVerifyUpdateBootstrapCommand(
                bundleURL: bundle,
                verificationInvocationId: invocationId
            )
        )

        let receipt = try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: Data(
                contentsOf: installed.updateBootstrapVerificationReceipt(
                    updateId: "update-0.2.2"
                )
            )
        )
        let binding = try JSONDecoder().decode(
            UpdateBootstrapVerificationInvocationBinding.self,
            from: Data(
                contentsOf: installed
                    .updateBootstrapVerificationInvocationBinding(
                        verificationInvocationId: invocationId
                    )
            )
        )
        XCTAssertEqual(receipt.verificationInvocationId, invocationId)
        XCTAssertEqual(binding.verificationInvocationId, invocationId)
        XCTAssertEqual(binding.updateId, receipt.updateId)
        XCTAssertEqual(
            binding.canonicalPayloadSHA256,
            receipt.canonicalPayloadSHA256
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installed
                    .platformAgentUpdateBootstrapVerificationEvidence(
                        verificationInvocationId: invocationId
                    ).path
            )
        )
    }

    func testProofReceiptOwnerStaysProductInstalledWhenLifecycleHomeIsNotInstalled() {
        let noninstalled = InstalledRuntimePaths(
            runtimeHome: URL(fileURLWithPath: "/var/root/.tirosh/vitalserver-vm")
        )
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: noninstalled.runtimeHome,
                installed: noninstalled,
                config: noninstalled.vmConfig,
                pidFile: noninstalled.pidFile
            )
        )
        let inputs = lifecycle.installedRootVerificationReceiptProofInputs(
            updateId: "update-42"
        )
        let product = InstalledRuntimePaths.defaultInstalled

        XCTAssertEqual(
            inputs.expectedResolvedRuntimeHome,
            product.runtimeHome.path
        )
        XCTAssertEqual(
            inputs.expectedTrustStorePath,
            product.updateBootstrapTrustStore.path
        )
        XCTAssertEqual(
            inputs.receiptURL,
            product.updateBootstrapVerificationReceipt(updateId: "update-42")
        )
        XCTAssertNotEqual(
            inputs.expectedResolvedRuntimeHome,
            noninstalled.runtimeHome.path
        )
        XCTAssertNotEqual(
            inputs.receiptURL,
            noninstalled.updateBootstrapVerificationReceipt(updateId: "update-42")
        )
        XCTAssertEqual(
            lifecycle.installedPaths.runtimeHome.path,
            noninstalled.runtimeHome.path
        )
    }

    func testFailedVerifyDoesNotPersistAReceipt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        let bundle = root.appendingPathComponent("incoming-update")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: bundle,
            withIntermediateDirectories: true
        )
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock()
        )

        XCTAssertThrowsError(try lifecycle.verifyUpdateBootstrap(bundle))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installed.updateBootstrapVerificationReceipt(
                    updateId: "update-0.2.2"
                ).path
            )
        )
    }

    func testVerifiedBundleHandsOffAndAtomicallySettlesInstalledRelease() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(productRoot: root.appendingPathComponent("product"))
        let bundle = root.appendingPathComponent("incoming-update")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: installed.updateBootstrapTrustStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installed.runtimeStateDatabase
        ).initialize()
        let repository = makeRepository(installed)
        try repository.settlePackageInstallRelease(
            try InstalledProductReleasePolicy.makePackageInstall(
                installationId: "installation-1",
                productId: Constants.Product.identifier,
                productVersion: "0.2.1",
                runtimeVersion: "0.2.1",
                installOperationId: "install-1",
                settledAt: "2026-07-27T00:00:00Z"
            )
        )

        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(bundle, privateKey: privateKey)

        let runner = SuccessfulUpdateBootstrapRunner()
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock(),
            commandRunner: runner,
            serviceManager: UpdateHandoffTestServiceManager(
                jobsRoot: installed.updateHandoffJobsDirectory,
                runner: runner
            ),
            guestAddressProvider: UpdateBootstrapGuestAddressProvider()
        )

        try lifecycle.applyUpdateBootstrap(
            RuntimeApplyUpdateBootstrapCommand(
                bundleURL: bundle,
                requestId: "request-1"
            )
        )

        guard case .loaded(let journal) =
            repository.loadUpdateBootstrapJournal(id: "update-0.2.2") else {
            return XCTFail("expected persisted update journal")
        }
        XCTAssertEqual(journal.state, .succeeded)
        XCTAssertEqual(journal.requestId, "request-1")
        XCTAssertNil(journal.platformAgentSelectionCorrelation)
        guard case .loaded(let release) =
            repository.loadInstalledProductRelease() else {
            return XCTFail("expected installed release")
        }
        XCTAssertEqual(release.productVersion, "0.2.2")
        XCTAssertEqual(release.runtimeVersion, "0.2.2")
        XCTAssertEqual(release.installationId, "installation-1")
        XCTAssertEqual(release.installationRevision, 2)
        XCTAssertEqual(release.releaseRevision, 2)
        XCTAssertEqual(release.source, .update)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(
            SQLiteRuntimeOperationLeaseRepository(
                databaseURL: installed.runtimeStateDatabase
            ).loadOperationLease(),
            .missing
        )
    }

    func testApplyDoesNotTreatUnreadablePlatformAgentCorrelationAsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(productRoot: root.appendingPathComponent("product"))
        let bundle = root.appendingPathComponent("incoming-update")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: installed.updateBootstrapTrustStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installed.runtimeStateDatabase
        ).initialize()
        let repository = makeRepository(installed)
        try repository.settlePackageInstallRelease(
            try InstalledProductReleasePolicy.makePackageInstall(
                installationId: "installation-1",
                productId: Constants.Product.identifier,
                productVersion: "0.2.1",
                runtimeVersion: "0.2.1",
                installOperationId: "install-1",
                settledAt: "2026-07-27T00:00:00Z"
            )
        )

        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(bundle, privateKey: privateKey)
        try FileManager.default.createDirectory(
            at: installed.platformAgentUpdateBootstrapVerifiedSelectionDirectory,
            withIntermediateDirectories: true
        )
        try Data("{".utf8).write(
            to: installed.platformAgentUpdateBootstrapVerifiedSelection
        )

        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock(),
            commandRunner: SuccessfulUpdateBootstrapRunner(),
            serviceManager: UpdateHandoffTestServiceManager(
                jobsRoot: installed.updateHandoffJobsDirectory,
                runner: SuccessfulUpdateBootstrapRunner()
            ),
            guestAddressProvider: UpdateBootstrapGuestAddressProvider()
        )

        XCTAssertThrowsError(
            try lifecycle.applyUpdateBootstrap(
                RuntimeApplyUpdateBootstrapCommand(
                    bundleURL: bundle,
                    requestId: "request-1",
                    requirePlatformAgentSelection: true
                )
            )
        ) { error in
            guard let compositionError =
                error as? RuntimeUpdateBootstrapCompositionError,
                case .platformAgentApplyCorrelationDecodeFailed =
                    compositionError
            else {
                return XCTFail("expected decode failure, got \(error)")
            }
        }
        guard case .missing =
            repository.loadUpdateBootstrapJournal(id: "update-0.2.2") else {
            return XCTFail("corrupt correlation must not admit a journal")
        }
    }

    func testRequiredPlatformAgentSelectionMissingIsFatalAndOrdinaryApplyIgnoresStore()
        throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        let bundle = root.appendingPathComponent("incoming-update")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: installed.updateBootstrapTrustStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installed.runtimeStateDatabase
        ).initialize()
        let repository = makeRepository(installed)
        try repository.settlePackageInstallRelease(
            try InstalledProductReleasePolicy.makePackageInstall(
                installationId: "installation-1",
                productId: Constants.Product.identifier,
                productVersion: "0.2.1",
                runtimeVersion: "0.2.1",
                installOperationId: "install-1",
                settledAt: "2026-07-27T00:00:00Z"
            )
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(bundle, privateKey: privateKey)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock(),
            commandRunner: SuccessfulUpdateBootstrapRunner(),
            serviceManager: UpdateHandoffTestServiceManager(
                jobsRoot: installed.updateHandoffJobsDirectory,
                runner: SuccessfulUpdateBootstrapRunner()
            ),
            guestAddressProvider: UpdateBootstrapGuestAddressProvider()
        )

        XCTAssertThrowsError(
            try lifecycle.applyUpdateBootstrap(
                RuntimeApplyUpdateBootstrapCommand(
                    bundleURL: bundle,
                    requestId: "request-required",
                    requirePlatformAgentSelection: true
                )
            )
        ) { error in
            guard let compositionError =
                error as? RuntimeUpdateBootstrapCompositionError,
                case .platformAgentSelectionRequiredMissing =
                    compositionError
            else {
                return XCTFail("expected required missing, got \(error)")
            }
        }
        guard case .missing =
            repository.loadUpdateBootstrapJournal(id: "update-0.2.2") else {
            return XCTFail("required missing must not admit a journal")
        }
    }

    func testResumesOnlyVerifiedPendingStagedHandoff() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        let staged = installed.updateBootstrapStagingDirectory
            .appendingPathComponent("update-0.2.2")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let repository = try prepareInstalledRelease(at: installed)
        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(staged, privateKey: privateKey)
        let envelope = try JSONDecoder().decode(
            UpdateBootstrapEnvelope.self,
            from: Data(
                contentsOf: staged.appendingPathComponent(
                    UpdateBootstrapBundleLayout.envelopeRelativePath
                )
            )
        )
        let admitted = recoveryJournal(
            envelope: envelope,
            state: .admitted,
            revision: 1
        )
        let pending = recoveryJournal(
            envelope: envelope,
            state: .handoffPending,
            revision: 2
        )
        try repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        try repository.saveUpdateBootstrapJournal(
            pending,
            expectedRevision: admitted.journalRevision
        )
        try seedActiveLease(pending, databaseURL: installed.runtimeStateDatabase)

        let runner = SuccessfulUpdateBootstrapRunner()
        let lifecycle = makeLifecycle(
            installed: installed,
            runner: runner
        )
        try lifecycle.resumeUpdateBootstrapHandoff(
            RuntimeUpdateBootstrapRecoveryCommand(
                updateId: "update-0.2.2"
            )
        )

        guard case .loaded(let journal) =
            repository.loadUpdateBootstrapJournal(id: "update-0.2.2") else {
            return XCTFail("expected recovered journal")
        }
        XCTAssertEqual(journal.state, .succeeded)
        XCTAssertEqual(runner.invocations.count, 1)
    }

    func testSettlesRunningReceiptWithoutRelaunchingUpdater() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        let staged = installed.updateBootstrapStagingDirectory
            .appendingPathComponent("update-0.2.2")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let repository = try prepareInstalledRelease(at: installed)
        let privateKey = Curve25519.Signing.PrivateKey()
        try writeTrustStore(
            privateKey.publicKey.rawRepresentation,
            to: installed.updateBootstrapTrustStore
        )
        try writeSignedBundle(staged, privateKey: privateKey)
        let envelope = try JSONDecoder().decode(
            UpdateBootstrapEnvelope.self,
            from: Data(
                contentsOf: staged.appendingPathComponent(
                    UpdateBootstrapBundleLayout.envelopeRelativePath
                )
            )
        )
        let admitted = recoveryJournal(
            envelope: envelope,
            state: .admitted,
            revision: 1
        )
        let pending = recoveryJournal(
            envelope: envelope,
            state: .handoffPending,
            revision: 2
        )
        let running = recoveryJournal(
            envelope: envelope,
            state: .running,
            revision: 3
        )
        try repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )
        try repository.saveUpdateBootstrapJournal(
            pending,
            expectedRevision: admitted.journalRevision
        )
        try repository.saveUpdateBootstrapJournal(
            running,
            expectedRevision: pending.journalRevision
        )
        let handoff = staged.appendingPathComponent("handoff")
        try FileManager.default.createDirectory(
            at: handoff,
            withIntermediateDirectories: true
        )
        let report = Data("{\"result\":\"succeeded\"}\n".utf8)
        try report.write(
            to: handoff.appendingPathComponent("report.json")
        )
        let receipt = UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: running.id,
            requestId: running.requestId,
            bootstrapEnvelopeId: running.envelope.id,
            updateSpecificationSHA256:
                running.envelope.specification.sha256,
            expectedJournalRevision: running.journalRevision,
            outcome: .succeeded,
            reportRelativePath: "handoff/report.json",
            reportSHA256: sha256(report),
            failureReason: nil,
            finishedAt: "2026-07-27T00:10:00Z"
        )
        try JSONEncoder().encode(receipt).write(
            to: handoff.appendingPathComponent(
                "completion-receipt.json"
            )
        )
        try seedActiveLease(running, databaseURL: installed.runtimeStateDatabase)

        let runner = SuccessfulUpdateBootstrapRunner()
        let lifecycle = makeLifecycle(
            installed: installed,
            runner: runner
        )
        try lifecycle.settleUpdateBootstrapHandoff(
            RuntimeUpdateBootstrapRecoveryCommand(
                updateId: running.id
            )
        )

        guard case .loaded(let journal) =
            repository.loadUpdateBootstrapJournal(id: running.id) else {
            return XCTFail("expected settled journal")
        }
        XCTAssertEqual(journal.state, .succeeded)
        XCTAssertEqual(runner.invocations.count, 0)
    }

    func testExplicitlyFailsPersistedNonTerminalJournalWithReason() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let installed = InstalledRuntimePaths(
            productRoot: root.appendingPathComponent("product")
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let repository = try prepareInstalledRelease(at: installed)
        let privateKey = Curve25519.Signing.PrivateKey()
        let bundle = root.appendingPathComponent("bundle")
        try writeSignedBundle(bundle, privateKey: privateKey)
        let envelope = try JSONDecoder().decode(
            UpdateBootstrapEnvelope.self,
            from: Data(
                contentsOf: bundle.appendingPathComponent(
                    UpdateBootstrapBundleLayout.envelopeRelativePath
                )
            )
        )
        let admitted = recoveryJournal(
            envelope: envelope,
            state: .admitted,
            revision: 1
        )
        try repository.saveUpdateBootstrapJournal(
            admitted,
            expectedRevision: nil
        )

        let lifecycle = makeLifecycle(
            installed: installed,
            runner: SuccessfulUpdateBootstrapRunner()
        )
        try lifecycle.failUpdateBootstrap(
            RuntimeFailUpdateBootstrapCommand(
                updateId: admitted.id,
                reason: "operator confirmed source bundle was lost"
            )
        )

        guard case .loaded(let journal) =
            repository.loadUpdateBootstrapJournal(id: admitted.id) else {
            return XCTFail("expected failed journal")
        }
        XCTAssertEqual(journal.state, .failed)
        XCTAssertEqual(
            journal.failureReason,
            "operator confirmed source bundle was lost"
        )
    }

    private func prepareInstalledRelease(
        at installed: InstalledRuntimePaths
    ) throws -> SQLiteUpdateBootstrapJournalRepository {
        try FileManager.default.createDirectory(
            at: installed.updateBootstrapTrustStore
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installed.runtimeStateDatabase
        ).initialize()
        let repository = makeRepository(installed)
        try repository.settlePackageInstallRelease(
            try InstalledProductReleasePolicy.makePackageInstall(
                installationId: "installation-1",
                productId: Constants.Product.identifier,
                productVersion: "0.2.1",
                runtimeVersion: "0.2.1",
                installOperationId: "install-1",
                settledAt: "2026-07-27T00:00:00Z"
            )
        )
        return repository
    }

    private func makeLifecycle(
        installed: InstalledRuntimePaths,
        runner: SuccessfulUpdateBootstrapRunner
    ) -> RuntimeLifecycle {
        RuntimeLifecycle(
            paths: LauncherPaths(
                home: installed.runtimeHome,
                installed: installed,
                config: installed.vmConfig,
                pidFile: installed.pidFile
            ),
            clock: UpdateBootstrapFixedClock(),
            commandRunner: runner,
            serviceManager: UpdateHandoffTestServiceManager(
                jobsRoot: installed.updateHandoffJobsDirectory,
                runner: runner
            ),
            guestAddressProvider: UpdateBootstrapGuestAddressProvider()
        )
    }

    private func recoveryJournal(
        envelope: UpdateBootstrapEnvelope,
        state: UpdateBootstrapJournalState,
        revision: Int
    ) -> UpdateBootstrapJournal {
        let isAdmitted = state == .admitted
        return UpdateBootstrapJournal(
            schemaVersion: "v2",
            id: envelope.id,
            journalRevision: revision,
            operationId: "operation-1",
            targetInstallationId: "installation-1",
            expectedInstallationRevision: 1,
            requestId: "request-1",
            envelope: envelope,
            bootstrapSignedSHA256: envelope.signature.signedSha256,
            state: state,
            stagedUpdaterRelativePath:
                isAdmitted
                ? nil : envelope.nextUpdaterArtifact.relativePath,
            stagedSpecificationRelativePath:
                isAdmitted ? nil : envelope.specification.relativePath,
            completion: nil,
            failureReason: nil,
            createdAt: "2026-07-27T00:00:00Z",
            updatedAt: "2026-07-27T00:01:00Z"
        )
    }

    private func makeRepository(
        _ installed: InstalledRuntimePaths
    ) -> SQLiteUpdateBootstrapJournalRepository {
        SQLiteUpdateBootstrapJournalRepository(
            databaseURL: installed.runtimeStateDatabase,
            validate: ValidateUpdateBootstrapJournalUseCase().validate,
            validateRelease: InstalledProductReleasePolicy.validate,
            validateSettlement: InstalledProductReleasePolicy.validate
        )
    }

    private func seedActiveLease(
        _ journal: UpdateBootstrapJournal,
        databaseURL: URL
    ) throws {
        try SQLiteRuntimeOperationLeaseRepository(databaseURL: databaseURL)
            .acquire(
                RuntimeOperationLeaseDocument(
                    operationId: journal.operationId,
                    operation: .applyUpdateBootstrap,
                    targetInstallationId: journal.targetInstallationId,
                    expectedInstallationRevision:
                        journal.expectedInstallationRevision,
                    ownerPID: 123,
                    startedAt: "2026-07-27T00:00:00Z",
                    heartbeatAt: "2026-07-27T00:00:00Z",
                    expiresAt: "2026-07-27T01:00:00Z",
                    message: nil
                )
            )
    }

    private func writeTrustStore(_ publicKey: Data, to url: URL) throws {
        let store = UpdateBootstrapTrustStore(
            schemaVersion: "v2",
            keys: [
                TrustedUpdatePublisherKey(
                    id: "release-key-1",
                    algorithm: .ed25519,
                    publicKey: publicKey.base64EncodedString(),
                    state: .active
                ),
            ]
        )
        try JSONEncoder().encode(store).write(to: url, options: .atomic)
    }

    private func writeSignedBundle(
        _ root: URL,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws {
        let updaterData = Data("#!/bin/sh\nexit 0\n".utf8)
        var payloads: [(artifact: UpdateBootstrapArtifact, data: Data, executable: Bool)] = []
        func declaredArtifact(
            id: String,
            relativePath: String,
            mediaType: String = "application/octet-stream",
            executable: Bool = false
        ) -> UpdateBootstrapArtifact {
            let data = Data("\(id)\n".utf8)
            let artifact = UpdateBootstrapArtifact(
                id: id,
                relativePath: relativePath,
                sha256: sha256(data),
                sizeBytes: data.count,
                mediaType: mediaType
            )
            payloads.append((artifact, data, executable))
            return artifact
        }
        let layers: [UpdateLayer] = [
            .container,
            .guestRuntime,
            .hostPlatform,
        ]
        let layerPlan = layers.enumerated().map { index, layer in
            let base = "payload/layers/\(layer.rawValue)"
            let executor = declaredArtifact(
                id: "\(layer.rawValue)-executor",
                relativePath: "\(base)/effect-executor",
                mediaType: BundleOwnedProductUpdatePlanner
                    .effectExecutorMediaType,
                executable: true
            )
            return ProductUpdateLayerPlan(
                layer: layer,
                dependsOn: index == 0 ? [] : [layers[index - 1]],
                artifact: declaredArtifact(
                    id: "\(layer.rawValue)-apply",
                    relativePath: "\(base)/artifact"
                ),
                effectExecutor: ProductUpdateLayerEffectExecutor(
                    id: executor.id,
                    relativePath: executor.relativePath,
                    sha256: executor.sha256,
                    sizeBytes: executor.sizeBytes,
                    mediaType: executor.mediaType,
                    configurationArtifact: declaredArtifact(
                        id: "\(layer.rawValue)-configuration",
                        relativePath: "\(base)/effect-configuration.json",
                        mediaType: BundleOwnedProductUpdatePlanner
                            .effectConfigurationMediaType
                    )
                ),
                rollback: ProductUpdateLayerRollbackPlan(
                    state: .available,
                    artifact: declaredArtifact(
                        id: "\(layer.rawValue)-rollback",
                        relativePath: "\(base)/rollback-artifact"
                    ),
                    reason: nil
                )
            )
        }
        let productSpecification = ProductUpdateSpecification(
            schemaVersion: BundleOwnedProductUpdatePlanner
                .specificationSchemaVersion,
            id: "update-specification",
            bootstrapEnvelopeId: "update-0.2.2",
            layerPlan: layerPlan
        )
        let specificationEncoder = JSONEncoder()
        specificationEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let specificationData = try specificationEncoder.encode(
            productSpecification
        )
        let updater = UpdateBootstrapArtifact(
            id: "next-updater",
            relativePath: "payload/bin/vitalserver-update",
            sha256: sha256(updaterData),
            sizeBytes: updaterData.count,
            mediaType: "application/octet-stream"
        )
        let specification = UpdateBootstrapArtifact(
            id: "update-specification",
            relativePath: "payload/update-specification.json",
            sha256: sha256(specificationData),
            sizeBytes: specificationData.count,
            mediaType: "application/json"
        )
        let unsigned = envelope(
            updater: updater,
            specification: specification,
            payloadArtifacts: payloads.map(\.artifact),
            signedSHA256: String(repeating: "0", count: 64),
            signature: "unsigned"
        )
        let payload = try UpdateBootstrapCanonicalPayloadEncoder().encode(unsigned)
        let signedSHA256 = sha256(payload)
        let signature = try privateKey.signature(for: payload)
            .base64EncodedString()
        let signed = envelope(
            updater: updater,
            specification: specification,
            payloadArtifacts: payloads.map(\.artifact),
            signedSHA256: signedSHA256,
            signature: signature
        )

        let updaterURL = root.appendingPathComponent(updater.relativePath)
        let specificationURL = root.appendingPathComponent(
            specification.relativePath
        )
        try FileManager.default.createDirectory(
            at: updaterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: specificationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updaterData.write(to: updaterURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: updaterURL.path
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: updaterURL.path)
        )
        try specificationData.write(to: specificationURL)
        for payload in payloads {
            let url = root.appendingPathComponent(
                payload.artifact.relativePath
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.data.write(to: url)
            if payload.executable {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: url.path
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(signed).write(
            to: root.appendingPathComponent(
                UpdateBootstrapBundleLayout.envelopeRelativePath
            ),
            options: .atomic
        )
    }

    private func envelope(
        updater: UpdateBootstrapArtifact,
        specification: UpdateBootstrapArtifact,
        payloadArtifacts: [UpdateBootstrapArtifact],
        signedSHA256: String,
        signature: String
    ) -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v2",
            id: "update-0.2.2",
            productId: Constants.Product.identifier,
            target: UpdateBootstrapTarget(
                platform: .macos,
                architecture: .arm64
            ),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: updater,
            specification: specification,
            payloadArtifacts: payloadArtifacts,
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key-1",
                signedSha256: signedSHA256,
                value: signature
            ),
            issuedAt: "2026-07-27T00:00:00Z"
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct UpdateBootstrapGuestAddressProvider:
    RuntimeGuestAddressProvider
{
    func readGuestAddress() -> RuntimeGuestAddressReadResult {
        .loaded(
            address: "192.168.64.3",
            source: .platformAgent
        )
    }
}

private struct UpdateBootstrapFixedClock: RuntimeClock {
    let now = Date(timeIntervalSince1970: 1_785_110_400)
}

private final class SuccessfulUpdateBootstrapRunner: RuntimeCommandRunner {
    private(set) var invocations: [UpdateBootstrapHandoffInvocation] = []

    func run(
        _ executable: String,
        arguments: [String]
    ) -> RuntimeProcessResult {
        guard arguments.count == 3,
              arguments[0] == "execute",
              arguments[1] == "--invocation" else {
            return RuntimeProcessResult(
                exitCode: 64,
                stdout: "",
                stderr: "unexpected invocation"
            )
        }
        let invocationURL = URL(fileURLWithPath: arguments[2])
        do {
            let invocation = try JSONDecoder().decode(
                UpdateBootstrapHandoffInvocation.self,
                from: Data(contentsOf: invocationURL)
            )
            invocations.append(invocation)
            let stagedRoot = invocationURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let reportData = Data("{\"result\":\"succeeded\"}\n".utf8)
            let reportRelativePath = "handoff/report.json"
            let reportURL = stagedRoot.appendingPathComponent(reportRelativePath)
            try reportData.write(to: reportURL, options: .atomic)
            let receipt = UpdateBootstrapCompletionReceipt(
                schemaVersion: "v1",
                updateId: invocation.updateId,
                requestId: invocation.requestId,
                bootstrapEnvelopeId: invocation.bootstrapEnvelopeId,
                updateSpecificationSHA256:
                    invocation.updateSpecificationSHA256,
                expectedJournalRevision: invocation.expectedJournalRevision,
                outcome: .succeeded,
                reportRelativePath: reportRelativePath,
                reportSHA256: SHA256.hash(data: reportData)
                    .map { String(format: "%02x", $0) }
                    .joined(),
                failureReason: nil,
                finishedAt: "2026-07-27T00:10:00Z"
            )
            let receiptURL = stagedRoot.appendingPathComponent(
                invocation.completionReceiptRelativePath
            )
            try JSONEncoder().encode(receipt).write(
                to: receiptURL,
                options: .atomic
            )
            return RuntimeProcessResult(
                exitCode: 0,
                stdout: "updated\n",
                stderr: ""
            )
        } catch {
            return RuntimeProcessResult(
                exitCode: 70,
                stdout: "",
                stderr: String(describing: error)
            )
        }
    }

    func runWritingOutput(
        _ executable: String,
        arguments: [String],
        output: URL
    ) -> RuntimeProcessResult {
        RuntimeProcessResult(
            exitCode: 64,
            stdout: "",
            stderr: "unexpected output-file invocation"
        )
    }
}

private final class UpdateHandoffTestServiceManager: RuntimeServiceManager {
    private let jobsRoot: URL
    private let runner: SuccessfulUpdateBootstrapRunner
    private var loaded: Set<String> = []

    init(jobsRoot: URL, runner: SuccessfulUpdateBootstrapRunner) {
        self.jobsRoot = jobsRoot
        self.runner = runner
    }

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        loaded.contains(service.label) ? .loaded : .notLoaded
    }

    func start(
        service: RuntimeManagedService,
        plist: String
    ) -> RuntimeProcessResult {
        guard service == .updateHandoffSupervisor else {
            return success()
        }
        do {
            try completeQueuedJobs()
            loaded.insert(service.label)
            return success()
        } catch {
            return RuntimeProcessResult(
                exitCode: 70,
                stdout: "",
                stderr: String(describing: error)
            )
        }
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        success()
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        loaded.remove(service.label)
        return success()
    }

    func setEnabled(
        service: RuntimeManagedService,
        enabled: Bool
    ) -> RuntimeProcessResult {
        success()
    }

    private func completeQueuedJobs() throws {
        let store = FileUpdateHandoffSupervisorStore(
            root: jobsRoot,
            validate: ValidateUpdateHandoffJobUseCase().validate
        )
        let manager = ManageUpdateHandoffJobUseCase()
        for queued in try store.loadAll() where queued.state == .queued {
            let claimed = try manager.launchClaimed(
                job: queued,
                launchId: "test-launch",
                observedAt: "2026-07-27T00:09:58Z"
            )
            try store.save(claimed, expectedRevision: queued.revision)
            let child = UpdateHandoffChildIdentity(
                launchId: "test-launch",
                processId: 42,
                processGroupId: 42,
                startedAt: "2026-07-27T00:09:59Z"
            )
            let running = try manager.childStarted(
                job: claimed,
                child: child,
                observedAt: "2026-07-27T00:09:59Z"
            )
            try store.save(running, expectedRevision: claimed.revision)
            let process = runner.run(
                queued.updaterPath,
                arguments: [
                    "execute",
                    "--invocation",
                    queued.invocationPath,
                ]
            )
            let completed = try manager.childCompleted(
                job: running,
                receipt: UpdateHandoffChildCompletionReceipt(
                    jobId: queued.jobId,
                    launchId: "test-launch",
                    processId: 42,
                    processGroupId: 42,
                    exitCode: process.exitCode,
                    launchFailureReason: process.executionIssue?.message,
                    finishedAt: "2026-07-27T00:10:00Z"
                ),
                observedAt: "2026-07-27T00:10:00Z"
            )
            try store.save(completed, expectedRevision: running.revision)
        }
    }

    private func success() -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
