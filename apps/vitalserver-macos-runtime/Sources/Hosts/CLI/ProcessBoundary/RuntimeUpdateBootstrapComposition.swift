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
    case installedReleaseMissing
    case installedReleaseReadFailed(reason: String)
    case operationSucceededButLeaseReleaseFailed(
        operationId: String,
        reason: String
    )
    case operationAndLeaseReleaseFailed(
        operationReason: String,
        operationId: String,
        releaseReason: String
    )
    case operationSucceededButMaterializedBundleCleanupFailed(
        path: String,
        reason: String
    )
    case operationAndMaterializedBundleCleanupFailed(
        operationReason: String,
        path: String,
        cleanupReason: String
    )
    case handoffJobConflict(jobId: String, reason: String)
    case completionReportDecodeFailed(path: String, reason: String)
    case platformOperationJournalMismatch(updateId: String)
    case platformOperationContractInvalid(reason: String)
}

extension RuntimeLifecycle {
    func verifyUpdateBootstrap(_ bundleURL: URL) throws {
        let materialized = try materializeRuntimeUpdateBundle(bundleURL)
        do {
            let verified = try loadAndVerifyUpdateBootstrapClosure(
                bundleRoot: materialized.bundleURL
            )
            try cleanupMaterializedUpdateBootstrapBundle(materialized)
            print("update bootstrap verified")
            print("update: \(verified.envelope.id)")
            print(
                "release: \(verified.envelope.targetRelease.productVersion)"
            )
            print(
                "digest: \(verified.verification.canonicalPayloadSHA256)"
            )
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

    func applyUpdateBootstrap(
        _ command: RuntimeApplyUpdateBootstrapCommand
    ) throws {
        let repository = updateBootstrapJournalRepository()
        let leaseTarget: InstalledProductRelease
        switch repository.loadInstalledProductRelease() {
        case .loaded(let release):
            try ValidateInstalledProductReleaseUseCase().validate(release)
            leaseTarget = release
        case .missing:
            throw RuntimeUpdateBootstrapCompositionError.installedReleaseMissing
        case .failed(let reason):
            throw RuntimeUpdateBootstrapCompositionError
                .installedReleaseReadFailed(reason: reason)
        }
        let lease = try acquireRuntimeOperationLease(
            .applyUpdateBootstrap,
            targetInstallationId: leaseTarget.installationId,
            expectedInstallationRevision: leaseTarget.installationRevision
        )
        do {
            try applyUpdateBootstrapWithOwnedLease(command, lease: lease)
            do {
                try releaseRuntimeOperationLease(lease)
            } catch {
                throw RuntimeUpdateBootstrapCompositionError
                    .operationSucceededButLeaseReleaseFailed(
                        operationId: lease.operationId,
                        reason: String(describing: error)
                    )
            }
        } catch let operationError {
            if case RuntimeUpdateBootstrapCompositionError
                .operationSucceededButLeaseReleaseFailed = operationError {
                throw operationError
            }
            do {
                try releaseRuntimeOperationLease(lease)
            } catch let releaseError {
                throw RuntimeUpdateBootstrapCompositionError
                    .operationAndLeaseReleaseFailed(
                        operationReason: String(describing: operationError),
                        operationId: lease.operationId,
                        releaseReason: String(describing: releaseError)
                    )
            }
            throw operationError
        }
    }

    private func applyUpdateBootstrapWithOwnedLease(
        _ command: RuntimeApplyUpdateBootstrapCommand,
        lease: RuntimeOperationLeaseDocument
    ) throws {
        try heartbeatRuntimeOperationLease(lease)
        let materialized = try materializeRuntimeUpdateBundle(
            command.bundleURL
        )
        do {
            let output = try executeUpdateBootstrap(
                bundleRoot: materialized.bundleURL,
                requestId: command.requestId,
                lease: lease
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
        requestId: String,
        lease: RuntimeOperationLeaseDocument
    ) throws -> UpdateBootstrapHandoffWorkflowOutput {
        let verifiedBundle = try loadAndVerifyUpdateBootstrapClosure(
            bundleRoot: bundleRoot
        )
        let envelope = verifiedBundle.envelope
        let verification = verifiedBundle.verification

        let repository = updateBootstrapJournalRepository()
        let currentRelease = try RequireUpdateBootstrapAdmissionStateUseCase()
            .requireNewAdmission(
                installedRelease: repository.loadInstalledProductRelease(),
                journalId: envelope.id,
                journal: repository.loadUpdateBootstrapJournal(id: envelope.id)
            )
        try ValidateInstalledProductReleaseUseCase().validate(currentRelease)
        guard currentRelease.installationId == lease.targetInstallationId,
              currentRelease.installationRevision == lease.expectedInstallationRevision else {
            throw RuntimeUpdateBootstrapCompositionError.installedReleaseReadFailed(
                reason: "installed release changed after operation lease acquisition"
            )
        }

        let admittedAt = updateBootstrapTimestamp()
        let journal = try AdmitUpdateBootstrapUseCase().admit(
            envelope: envelope,
            verification: verification,
            operationId: lease.operationId,
            installedRelease: currentRelease,
            requestId: requestId,
            admittedAt: admittedAt
        )
        let advance = AdvanceUpdateBootstrapJournalUseCase()
        let invocationWriter = updateBootstrapInvocationWriter()
        let launcher = durableUpdateBootstrapHandoffLauncher()
        let receiptReader = updateBootstrapReceiptReader()

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
                verifyStagedClosure: { stagedRoot in
                    try loadAndVerifyUpdateBootstrapClosure(
                        bundleRoot: stagedRoot
                    ).verification
                },
                requireStagedProofMatch:
                    UpdateBootstrapStagedProofPolicy.requireMatch,
                verifiedAndStaged: advance.verifiedAndStaged,
                handoffStarted: advance.handoffStarted,
                makeInvocation:
                    MakeUpdateBootstrapHandoffInvocationUseCase().execute,
                writeInvocation: invocationWriter.write,
                launch: { invocation, invocationURL, stagedBundleRoot in
                    try heartbeatRuntimeOperationLease(lease)
                    let result = try launcher.launch(
                        jobId: updateHandoffJobId(invocation),
                        invocation: invocation,
                        invocationURL: invocationURL,
                        stagedBundleRoot: stagedBundleRoot
                    )
                    try heartbeatRuntimeOperationLease(lease)
                    return result
                },
                readReceipt: receiptReader.readCompletionReceipt,
                settle: SettleUpdateBootstrapHandoffUseCase().execute,
                readReport:
                    updateBootstrapReportReader().readCompletionReport,
                verifyReport:
                    VerifyUpdateBootstrapCompletionReportUseCase().verify,
                makeInstalledRelease: { settledJournal in
                    try MakeInstalledProductReleaseUseCase().makeUpdate(
                        from: settledJournal,
                        currentRelease:
                            repository.loadInstalledProductRelease()
                    )
                },
                settleSucceeded: { settled, release, journalRevision, installationRevision in
                    try repository.settleSucceededUpdate(
                        journal: settled,
                        release: release,
                        expectedJournalRevision: journalRevision,
                        expectedInstallationRevision: installationRevision
                    )
                },
                fail: advance.failed,
                now: updateBootstrapTimestamp,
                describeFailure: { String(describing: $0) }
            )
        )
    }

    func resumeUpdateBootstrapHandoff(
        _ command: RuntimeUpdateBootstrapRecoveryCommand
    ) throws {
        let repository = updateBootstrapJournalRepository()
        let pending = try RequireUpdateBootstrapRecoveryStateUseCase()
            .requireJournal(
                id: command.updateId,
                action: .resumeHandoff,
                journalRead: repository.loadUpdateBootstrapJournal(
                    id: command.updateId
                )
            )
        let stagedRoot = installedPaths.updateBootstrapStagingDirectory
            .appendingPathComponent(pending.id, isDirectory: true)
        let verifiedBundle = try loadAndVerifyUpdateBootstrapClosure(
            bundleRoot: stagedRoot
        )
        try ValidateUpdateBootstrapRecoveryClosureUseCase().validate(
            journal: pending,
            stagedEnvelope: verifiedBundle.envelope,
            verification: verifiedBundle.verification
        )

        let advance = AdvanceUpdateBootstrapJournalUseCase()
        let output = try ResumeUpdateBootstrapHandoffWorkflow().run(
            input: ResumeUpdateBootstrapHandoffWorkflowInput(
                pendingJournal: pending,
                stagedRoot: stagedRoot
            ),
            operations: ResumeUpdateBootstrapHandoffWorkflowOperations(
                saveJournal: { journal, expectedRevision in
                    try repository.saveUpdateBootstrapJournal(
                        journal,
                        expectedRevision: expectedRevision
                    )
                },
                handoffStarted: advance.handoffStarted,
                makeInvocation:
                    MakeUpdateBootstrapHandoffInvocationUseCase().execute,
                writeInvocation: updateBootstrapInvocationWriter().write,
                launch: { invocation, invocationURL, stagedBundleRoot in
                    try durableUpdateBootstrapHandoffLauncher().launch(
                        jobId: updateHandoffJobId(invocation),
                        invocation: invocation,
                        invocationURL: invocationURL,
                        stagedBundleRoot: stagedBundleRoot
                    )
                },
                readReceipt:
                    updateBootstrapReceiptReader().readCompletionReceipt,
                settle: SettleUpdateBootstrapHandoffUseCase().execute,
                readReport:
                    updateBootstrapReportReader().readCompletionReport,
                verifyReport:
                    VerifyUpdateBootstrapCompletionReportUseCase().verify,
                makeInstalledRelease: { settledJournal in
                    try MakeInstalledProductReleaseUseCase().makeUpdate(
                        from: settledJournal,
                        currentRelease:
                            repository.loadInstalledProductRelease()
                    )
                },
                settleSucceeded: { settled, release, journalRevision, installationRevision in
                    try repository.settleSucceededUpdate(
                        journal: settled,
                        release: release,
                        expectedJournalRevision: journalRevision,
                        expectedInstallationRevision: installationRevision
                    )
                },
                fail: advance.failed,
                now: updateBootstrapTimestamp,
                describeFailure: { String(describing: $0) }
            )
        )
        print("update bootstrap handoff resumed")
        print("journal: \(output.journal.id)")
        print("state: \(output.journal.state.rawValue)")
        print("updater exit code: \(output.updaterExitCode)")
    }

    func settleUpdateBootstrapHandoff(
        _ command: RuntimeUpdateBootstrapRecoveryCommand
    ) throws {
        let repository = updateBootstrapJournalRepository()
        let running = try RequireUpdateBootstrapRecoveryStateUseCase()
            .requireJournal(
                id: command.updateId,
                action: .settleHandoff,
                journalRead: repository.loadUpdateBootstrapJournal(
                    id: command.updateId
                )
            )
        let stagedRoot = installedPaths.updateBootstrapStagingDirectory
            .appendingPathComponent(running.id, isDirectory: true)
        let settled = try SettleRunningUpdateBootstrapWorkflow().run(
            input: SettleRunningUpdateBootstrapWorkflowInput(
                runningJournal: running,
                stagedRoot: stagedRoot
            ),
            operations: SettleRunningUpdateBootstrapWorkflowOperations(
                readReceipt:
                    updateBootstrapReceiptReader().readCompletionReceipt,
                settle: SettleUpdateBootstrapHandoffUseCase().execute,
                readReport:
                    updateBootstrapReportReader().readCompletionReport,
                verifyReport:
                    VerifyUpdateBootstrapCompletionReportUseCase().verify,
                saveJournal: { journal, expectedRevision in
                    try repository.saveUpdateBootstrapJournal(
                        journal,
                        expectedRevision: expectedRevision
                    )
                },
                makeInstalledRelease: { settledJournal in
                    try MakeInstalledProductReleaseUseCase().makeUpdate(
                        from: settledJournal,
                        currentRelease:
                            repository.loadInstalledProductRelease()
                    )
                },
                settleSucceeded: { settled, release, journalRevision, installationRevision in
                    try repository.settleSucceededUpdate(
                        journal: settled,
                        release: release,
                        expectedJournalRevision: journalRevision,
                        expectedInstallationRevision: installationRevision
                    )
                }
            )
        )
        print("update bootstrap handoff settled")
        print("journal: \(settled.id)")
        print("state: \(settled.state.rawValue)")
    }

    func failUpdateBootstrap(
        _ command: RuntimeFailUpdateBootstrapCommand
    ) throws {
        let repository = updateBootstrapJournalRepository()
        let current = try RequireUpdateBootstrapRecoveryStateUseCase()
            .requireJournal(
                id: command.updateId,
                action: .failNonTerminal,
                journalRead: repository.loadUpdateBootstrapJournal(
                    id: command.updateId
                )
            )
        let failed = try AdvanceUpdateBootstrapJournalUseCase().failed(
            journal: current,
            reason: command.reason,
            observedAt: updateBootstrapTimestamp()
        )
        try repository.saveUpdateBootstrapJournal(
            failed,
            expectedRevision: current.journalRevision
        )
        print("update bootstrap marked failed")
        print("journal: \(failed.id)")
        print("state: \(failed.state.rawValue)")
        print("reason: \(command.reason)")
    }

    func proveUpdateBootstrap(
        _ command: RuntimeProveUpdateBootstrapCommand
    ) throws {
        let repository = updateBootstrapJournalRepository()
        let proof = ProveUpdateBootstrapLifecycleUseCase()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let journal = try proof.awaitTerminalJournal(
            updateId: command.updateId,
            timeoutMilliseconds: command.timeoutMilliseconds,
            pollIntervalMilliseconds: command.pollIntervalMilliseconds,
            elapsedMilliseconds: {
                let elapsedNanoseconds =
                    DispatchTime.now().uptimeNanoseconds - startedAt
                return elapsedNanoseconds / 1_000_000
            },
            wait: { milliseconds in
                Thread.sleep(
                    forTimeInterval: Double(milliseconds) / 1_000
                )
            },
            readJournal: {
                repository.loadUpdateBootstrapJournal(id: command.updateId)
            }
        )
        guard let completion = journal.completion else {
            throw ProveUpdateBootstrapLifecycleError.completionMissing(
                id: journal.id
            )
        }
        let stagedRoot = installedPaths.updateBootstrapStagingDirectory
            .appendingPathComponent(journal.id, isDirectory: true)
        let input = try BundleOwnedProductUpdateInputReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: fileStore.pathState,
                fileSize: fileStore.fileSize,
                readData: fileStore.readData
            )
        ).read(
            invocationURL: stagedRoot
                .appendingPathComponent("handoff", isDirectory: true)
                .appendingPathComponent("invocation.json")
        )
        let reportRead = updateBootstrapReportReader().readCompletionReport(
            relativePath: completion.reportRelativePath,
            beneath: stagedRoot
        )
        try VerifyUpdateBootstrapCompletionReportUseCase().verify(
            settledJournal: journal,
            reportRead: reportRead
        )
        let reportURL = stagedRoot.appendingPathComponent(
            completion.reportRelativePath
        )
        let report: ProductUpdateExecutionReport
        do {
            report = try JSONDecoder().decode(
                ProductUpdateExecutionReport.self,
                from: fileStore.readData(reportURL)
            )
        } catch {
            throw RuntimeUpdateBootstrapCompositionError
                .completionReportDecodeFailed(
                    path: completion.reportRelativePath,
                    reason: String(describing: error)
                )
        }
        let plan = try PlanBundleOwnedProductUpdateUseCase().execute(
            invocation: input.invocation,
            specification: input.specification
        )
        try ValidateProductUpdateExecutionReportUseCase().execute(
            report: report,
            invocation: input.invocation,
            plan: plan
        )
        let proven = try proof.execute(
            expectation: command.expectation,
            journal: journal,
            report: report
        )
        let operationState = try RuntimeControlAPIOperationStateReader(
            baseURL: RuntimeControlAPIAutomationEndpoint().baseURL(),
            httpClient: RuntimeControlAPILocalSessionHTTPClient()
        ).loadOperationState()
        let platformJournalRead: UpdateBootstrapJournalReadResult
        switch operationState.stableUpdate.state {
        case .loaded:
            if let document = operationState.stableUpdate.document {
                platformJournalRead = .loaded(document)
            } else {
                throw RuntimeUpdateBootstrapCompositionError
                    .platformOperationContractInvalid(
                        reason: "loaded stable update resource has no document"
                    )
            }
        case .missing:
            platformJournalRead = .missing
        case .unavailable, .failed:
            guard let readError = operationState.stableUpdate.readError,
                  !readError.isEmpty else {
                throw RuntimeUpdateBootstrapCompositionError
                    .platformOperationContractInvalid(
                        reason:
                            "failed stable update resource has no read error"
                    )
            }
            platformJournalRead = .failed(
                reason: readError
            )
        }
        let platformJournal = try proof.requireJournal(
            updateId: command.updateId,
            journalRead: platformJournalRead
        )
        guard platformJournal == journal else {
            throw RuntimeUpdateBootstrapCompositionError
                .platformOperationJournalMismatch(updateId: command.updateId)
        }
        _ = try proof.execute(
            expectation: command.expectation,
            journal: platformJournal,
            report: report
        )
        print("update bootstrap lifecycle proof verified")
        print("journal: \(proven.id)")
        print("state: \(proven.state.rawValue)")
        print("expectation: \(command.expectation.rawValue)")
    }


    private func loadAndVerifyUpdateBootstrapClosure(
        bundleRoot: URL
    ) throws -> (
        envelope: UpdateBootstrapEnvelope,
        verification: VerifiedUpdateBootstrapClosure
    ) {
        let envelopeRead = FileUpdateBootstrapEnvelopeReader(
            bundleRoot: bundleRoot,
            fileStore: fileStore
        ).readEnvelope()
        let entriesRead = FileUpdateBootstrapBundleEntriesReader(
            bundleRoot: bundleRoot,
            fileStore: fileStore
        ).readEntries()
        let loaded = try LoadUpdateBootstrapBundleUseCase().load(
            envelopeRead: envelopeRead,
            entriesRead: entriesRead
        )
        let envelope = loaded.envelope

        let publisherKeys = try UpdateBootstrapTrustStoreReader(
            validate: UpdateBootstrapTrustStorePolicy.validate
        ).loadPublisherKeys(from: installedPaths.updateBootstrapTrustStore)
        let canonicalEncoder = UpdateBootstrapCanonicalPayloadEncoder()
        let signatureVerifier = UpdateBootstrapPublisherSignatureVerifier(
            publisherKeysById: publisherKeys
        )
        let artifactObserver = UpdateBootstrapArtifactFileObserver(
            bundleDirectory: bundleRoot
        )
        let envelopeVerification =
            try VerifyUpdateBootstrapEnvelopeUseCase().verify(
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
        let verification =
            try VerifyUpdateBootstrapPayloadClosureUseCase().verify(
                envelope: envelope,
                envelopeVerification: envelopeVerification,
                entries: loaded.entries,
                observeArtifact: artifactObserver.observe
            )

        return (envelope, verification)
    }

    private func updateBootstrapInvocationWriter(
    ) -> UpdateBootstrapHandoffInvocationWriter {
        UpdateBootstrapHandoffInvocationWriter(
            operations: UpdateBootstrapHandoffInvocationWriteOperations(
                pathState: fileStore.pathState,
                createDirectory: fileStore.createDirectory,
                writeData: fileStore.writeData
            )
        )
    }

    private func durableUpdateBootstrapHandoffLauncher(
    ) -> DurableUpdateBootstrapHandoffLauncher {
        let store = FileUpdateHandoffSupervisorStore(
            root: installedPaths.updateHandoffJobsDirectory,
            validate: ValidateUpdateHandoffJobUseCase().validate
        )
        let workflow = UpdateHandoffSupervisorWorkflow()
        let manager = ManageUpdateHandoffJobUseCase()
        return DurableUpdateBootstrapHandoffLauncher(
            operations: DurableUpdateBootstrapHandoffLaunchOperations(
                fileState: { url in
                    fileStore.fileState(atPath: url.path)
                },
                submit: { jobId, invocation, invocationURL, updaterURL in
                    let queued = manager.enqueue(
                        jobId: jobId,
                        updateId: invocation.updateId,
                        operationId: invocation.operationId,
                        invocationPath: invocationURL.path,
                        updaterPath: updaterURL.path,
                        observedAt: updateBootstrapTimestamp()
                    )
                    do {
                        try store.save(queued, expectedRevision: nil)
                        return queued
                    } catch FileUpdateHandoffSupervisorStoreError
                        .jobAlreadyExists {
                        let existing = try store.load(jobId: jobId)
                        guard existing.updateId == invocation.updateId,
                              existing.operationId == invocation.operationId,
                              existing.invocationPath == invocationURL.path,
                              existing.updaterPath == updaterURL.path else {
                            throw RuntimeUpdateBootstrapCompositionError
                                .handoffJobConflict(
                                    jobId: jobId,
                                    reason:
                                        "persisted job does not match invocation"
                                )
                        }
                        return existing
                    }
                },
                startSupervisor: {
                    try restartOrStartLaunchdService(
                        .updateHandoffSupervisor
                    )
                },
                waitForTerminal: { jobId in
                    try workflow.wait(
                        jobId: jobId,
                        attempts: 86_400,
                        load: { try store.load(jobId: jobId) },
                        pause: { sleeper.sleep(forTimeInterval: 0.25) }
                    )
                }
            )
        )
    }

    private func updateHandoffJobId(
        _ invocation: UpdateBootstrapHandoffInvocation
    ) -> String {
        updateBootstrapSHA256(
            Data(
                "\(invocation.updateId)\u{0}\(invocation.operationId)".utf8
            )
        )
    }

    private func updateBootstrapReceiptReader(
    ) -> UpdateBootstrapCompletionReceiptReader {
        UpdateBootstrapCompletionReceiptReader(
            pathState: fileStore.pathState,
            readData: fileStore.readData
        )
    }

    private func updateBootstrapReportReader(
    ) -> UpdateBootstrapCompletionReportReader {
        UpdateBootstrapCompletionReportReader(
            pathState: fileStore.pathState,
            readData: fileStore.readData,
            sha256: updateBootstrapSHA256
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
