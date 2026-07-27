import Application
import Bootstrap
import Contracts
import CryptoKit
import Domain
import Foundation
import InboundAdapters
import OutboundAdapters
import Workflow

enum RuntimeUpdateBootstrapCompositionError: Error, Equatable {
    case operationSucceededButMaterializedBundleCleanupFailed(
        path: String,
        reason: String
    )
    case operationAndMaterializedBundleCleanupFailed(
        operationReason: String,
        path: String,
        cleanupReason: String
    )
}

extension RuntimeLifecycle {
    func applyUpdateBootstrap(
        _ command: RuntimeApplyUpdateBootstrapCommand
    ) throws {
        let materialized = try materializeRuntimeUpdateBundle(
            command.bundleURL
        )
        do {
            let output = try executeUpdateBootstrap(
                bundleRoot: materialized.bundleURL,
                requestId: command.requestId
            )
            try cleanupMaterializedUpdateBootstrapBundle(materialized)
            print("update bootstrap handoff completed")
            print("journal: \(output.journal.id)")
            print("state: \(output.journal.state.rawValue)")
            print("updater exit code: \(output.updaterExitCode)")
        } catch {
            guard let temporaryRoot = materialized.temporaryRoot else {
                throw error
            }
            do {
                try fileStore.removeItem(at: temporaryRoot)
            } catch let cleanupError {
                throw RuntimeUpdateBootstrapCompositionError
                    .operationAndMaterializedBundleCleanupFailed(
                        operationReason: String(describing: error),
                        path: temporaryRoot.path,
                        cleanupReason: String(describing: cleanupError)
                    )
            }
            throw error
        }
    }

    private func executeUpdateBootstrap(
        bundleRoot: URL,
        requestId: String
    ) throws -> UpdateBootstrapHandoffWorkflowOutput {
        let envelopeRead = FileUpdateBootstrapEnvelopeReader(
            bundleRoot: bundleRoot,
            fileStore: fileStore
        ).readEnvelope()
        let entriesRead = FileUpdateBootstrapBundleEntriesReader(
            bundleRoot: bundleRoot,
            fileStore: fileStore
        ).readEntries()
        let envelope = try LoadUpdateBootstrapBundleUseCase().load(
            envelopeRead: envelopeRead,
            entriesRead: entriesRead
        )

        let repository = updateBootstrapJournalRepository()
        let currentRelease = try RequireUpdateBootstrapAdmissionStateUseCase()
            .requireNewAdmission(
                installedRelease: repository.loadInstalledProductRelease(),
                journalId: envelope.id,
                journal: repository.loadUpdateBootstrapJournal(id: envelope.id)
            )
        try ValidateInstalledProductReleaseUseCase().validate(currentRelease)

        let publicKeys = try UpdateBootstrapTrustStoreReader(
            validate: UpdateBootstrapTrustStorePolicy.validate
        ).loadPublicKeys(from: installedPaths.updateBootstrapTrustStore)
        let canonicalEncoder = UpdateBootstrapCanonicalPayloadEncoder()
        let signatureVerifier = UpdateBootstrapPublisherSignatureVerifier(
            publicKeysById: publicKeys
        )
        let artifactObserver = UpdateBootstrapArtifactFileObserver(
            bundleDirectory: bundleRoot
        )
        let verification = try VerifyUpdateBootstrapEnvelopeUseCase().verify(
            input: VerifyUpdateBootstrapEnvelopeInput(
                envelope: envelope,
                expectedProductId: Constants.Product.identifier,
                expectedTarget: UpdateBootstrapTarget(
                    platform: .macos,
                    architecture: .arm64
                )
            ),
            operations: VerifyUpdateBootstrapEnvelopeOperations(
                canonicalSignedPayload: canonicalEncoder.encode,
                sha256: updateBootstrapSHA256,
                verifyPublisherSignature: signatureVerifier.verify,
                observeArtifact: artifactObserver.observe
            )
        )

        let admittedAt = updateBootstrapTimestamp()
        let journal = try AdmitUpdateBootstrapUseCase().admit(
            envelope: envelope,
            verification: verification,
            operationId: UUID().uuidString.lowercased(),
            requestId: requestId,
            admittedAt: admittedAt
        )
        let advance = AdvanceUpdateBootstrapJournalUseCase()
        let invocationWriter = UpdateBootstrapHandoffInvocationWriter(
            operations: UpdateBootstrapHandoffInvocationWriteOperations(
                pathState: fileStore.pathState,
                createDirectory: fileStore.createDirectory,
                writeData: fileStore.writeData
            )
        )
        let launcher = UpdateBootstrapHandoffProcessLauncher(
            operations: UpdateBootstrapHandoffProcessLaunchOperations(
                fileState: { url in
                    fileStore.fileState(atPath: url.path)
                },
                run: { executable, arguments in
                    runProcess(executable, arguments: arguments)
                }
            )
        )
        let receiptReader = UpdateBootstrapCompletionReceiptReader(
            pathState: fileStore.pathState,
            readData: fileStore.readData
        )

        return try UpdateBootstrapHandoffWorkflow().run(
            input: UpdateBootstrapHandoffWorkflowInput(
                admittedJournal: journal,
                verification: verification,
                staging: UpdateBootstrapStagingInput(
                    updateId: envelope.id,
                    stagingAttemptId: UUID().uuidString.lowercased(),
                    sourceBundle: bundleRoot
                )
            ),
            operations: UpdateBootstrapHandoffWorkflowOperations(
                saveJournal: repository.saveUpdateBootstrapJournal,
                stage: immutableUpdateBootstrapStager().stage,
                verifiedAndStaged: advance.verifiedAndStaged,
                handoffStarted: advance.handoffStarted,
                makeInvocation:
                    MakeUpdateBootstrapHandoffInvocationUseCase().execute,
                writeInvocation: invocationWriter.write,
                launch: launcher.launch,
                readReceipt: receiptReader.readCompletionReceipt,
                settle: SettleUpdateBootstrapHandoffUseCase().execute,
                makeInstalledRelease: { settledJournal in
                    try MakeInstalledProductReleaseUseCase().makeUpdate(
                        from: settledJournal,
                        currentRelease:
                            repository.loadInstalledProductRelease()
                    )
                },
                settleSucceeded: { settled, release, journalRevision, releaseRevision in
                    try repository.settleSucceededUpdate(
                        journal: settled,
                        release: release,
                        expectedJournalRevision: journalRevision,
                        expectedReleaseRevision: releaseRevision
                    )
                },
                fail: advance.failed,
                now: updateBootstrapTimestamp,
                describeFailure: { String(describing: $0) }
            )
        )
    }

    private func updateBootstrapJournalRepository(
    ) -> SQLiteUpdateBootstrapJournalRepository {
        SQLiteUpdateBootstrapJournalRepository(
            databaseURL: installedPaths.runtimeStateDatabase,
            validate: ValidateUpdateBootstrapJournalUseCase().validate,
            validateRelease: InstalledProductReleasePolicy.validate,
            validateSettlement: InstalledProductReleasePolicy.validate
        )
    }

    private func immutableUpdateBootstrapStager(
    ) -> ImmutableUpdateBootstrapStager {
        ImmutableUpdateBootstrapStager(
            stagingRoot: installedPaths.updateBootstrapStagingDirectory,
            operations: ImmutableUpdateBootstrapStagingOperations(
                pathState: fileStore.pathState,
                createDirectory: fileStore.createDirectory,
                copyItem: fileStore.copyItem,
                moveItem: fileStore.moveItem,
                removeItem: fileStore.removeItem
            )
        )
    }

    private func cleanupMaterializedUpdateBootstrapBundle(
        _ materialized: RuntimeMaterializedBundle
    ) throws {
        guard let temporaryRoot = materialized.temporaryRoot else {
            return
        }
        do {
            try fileStore.removeItem(at: temporaryRoot)
        } catch {
            throw RuntimeUpdateBootstrapCompositionError
                .operationSucceededButMaterializedBundleCleanupFailed(
                    path: temporaryRoot.path,
                    reason: String(describing: error)
                )
        }
    }

    private func updateBootstrapTimestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now)
    }

    private func updateBootstrapSHA256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
