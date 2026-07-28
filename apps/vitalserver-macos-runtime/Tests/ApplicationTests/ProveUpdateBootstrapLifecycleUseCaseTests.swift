import Application
import Contracts
import XCTest

final class ProveUpdateBootstrapLifecycleUseCaseTests: XCTestCase {
    func testRequiresExplicitJournalReadSuccess() {
        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().requireJournal(
                updateId: "update-42",
                journalRead: .failed(reason: "database unavailable")
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .journalReadFailed(
                    id: "update-42",
                    reason: "database unavailable"
                )
            )
        }
    }

    func testAcceptsCorrelatedSuccessfulTerminalDocuments() throws {
        let journal = terminalJournal(
            state: .succeeded,
            outcome: .succeeded
        )
        let report = report(
            journal: journal,
            state: .succeeded,
            rollback: .notRequired
        )

        let proven = try ProveUpdateBootstrapLifecycleUseCase().execute(
            expectation: .succeeded,
            journal: journal,
            report: report
        )

        XCTAssertEqual(proven.id, journal.id)
    }

    func testAcceptsExplicitFailedAndRolledBackTerminalDocuments() throws {
        let journal = terminalJournal(
            state: .failed,
            outcome: .failed
        )
        let report = report(
            journal: journal,
            state: .failed,
            rollback: .succeeded
        )

        XCTAssertNoThrow(
            try ProveUpdateBootstrapLifecycleUseCase().execute(
                expectation: .failedRolledBack,
                journal: journal,
                report: report
            )
        )
    }

    func testWaitsForDelayedTerminalJournalWithoutGuessingCompletion() throws {
        let running = recoveryJournal(state: .running)
        let succeeded = terminalJournal(
            state: .succeeded,
            outcome: .succeeded
        )
        var reads = [running, running, succeeded]
        var elapsed: UInt64 = 0

        let journal = try ProveUpdateBootstrapLifecycleUseCase()
            .awaitTerminalJournal(
                updateId: succeeded.id,
                timeoutMilliseconds: 1_000,
                pollIntervalMilliseconds: 100,
                elapsedMilliseconds: { elapsed },
                wait: { elapsed += $0 },
                readJournal: { .loaded(reads.removeFirst()) }
            )

        XCTAssertEqual(journal.state, .succeeded)
        XCTAssertEqual(elapsed, 200)
        XCTAssertTrue(reads.isEmpty)
    }

    func testReportsLastOwnedStateWhenTerminalWaitTimesOut() {
        let running = recoveryJournal(state: .running)
        var elapsed: UInt64 = 0

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase()
                .awaitTerminalJournal(
                    updateId: running.id,
                    timeoutMilliseconds: 200,
                    pollIntervalMilliseconds: 100,
                    elapsedMilliseconds: { elapsed },
                    wait: { elapsed += $0 },
                    readJournal: { .loaded(running) }
                )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .terminalJournalWaitTimedOut(
                    id: running.id,
                    timeoutMilliseconds: 200,
                    lastState: .running
                )
            )
        }
    }

    func testRejectsRollbackProofWithoutHostFailureAndReverseReceipts() {
        let journal = terminalJournal(
            state: .failed,
            outcome: .failed
        )
        let report = ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            requestId: journal.requestId,
            bootstrapEnvelopeId: journal.envelope.id,
            updateSpecificationSHA256:
                journal.envelope.specification.sha256,
            state: .failed,
            startedAt: "2026-07-29T00:59:00Z",
            finishedAt: "2026-07-29T01:00:00Z",
            applyReceipts: [
                receipt(
                    journal: journal,
                    layer: .container,
                    operation: .apply,
                    state: .succeeded
                ),
                receipt(
                    journal: journal,
                    layer: .guestRuntime,
                    operation: .apply,
                    state: .failed
                ),
            ],
            rollbackReceipts: [
                receipt(
                    journal: journal,
                    layer: .container,
                    operation: .rollback,
                    state: .succeeded
                ),
            ],
            rollback: rollbackEvidence(.succeeded),
            failure: failureIssue()
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().execute(
                expectation: .failedRolledBack,
                journal: journal,
                report: report
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .hostFailureRollbackEvidenceInvalid(
                    applyLayers: [.container, .guestRuntime],
                    rollbackLayers: [.container]
                )
            )
        }
    }

    func testDoesNotTreatFailedWithoutRollbackAsRollbackProof() {
        let journal = terminalJournal(
            state: .failed,
            outcome: .failed
        )
        let report = report(
            journal: journal,
            state: .failed,
            rollback: .failed
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().execute(
                expectation: .failedRolledBack,
                journal: journal,
                report: report
            )
        )
    }

    private func terminalJournal(
        state: UpdateBootstrapJournalState,
        outcome: UpdateBootstrapCompletionOutcome
    ) -> UpdateBootstrapJournal {
        let base = recoveryJournal(state: .running)
        return UpdateBootstrapJournal(
            schemaVersion: base.schemaVersion,
            id: base.id,
            journalRevision: base.journalRevision + 1,
            operationId: base.operationId,
            targetInstallationId: base.targetInstallationId,
            expectedInstallationRevision:
                base.expectedInstallationRevision,
            requestId: base.requestId,
            envelope: base.envelope,
            bootstrapSignedSHA256: base.bootstrapSignedSHA256,
            state: state,
            stagedUpdaterRelativePath: base.stagedUpdaterRelativePath,
            stagedSpecificationRelativePath:
                base.stagedSpecificationRelativePath,
            completion: UpdateBootstrapCompletionReceipt(
                schemaVersion: "v1",
                updateId: base.id,
                requestId: base.requestId,
                bootstrapEnvelopeId: base.envelope.id,
                updateSpecificationSHA256:
                    base.envelope.specification.sha256,
                expectedJournalRevision: base.journalRevision,
                outcome: outcome,
                reportRelativePath: "handoff/report.json",
                reportSHA256: String(repeating: "c", count: 64),
                failureReason: outcome == .failed
                    ? "host effect failed"
                    : nil,
                finishedAt: "2026-07-29T01:00:00Z"
            ),
            failureReason: outcome == .failed
                ? "host effect failed"
                : nil,
            createdAt: base.createdAt,
            updatedAt: "2026-07-29T01:00:00Z"
        )
    }

    private func report(
        journal: UpdateBootstrapJournal,
        state: ProductUpdateExecutionState,
        rollback: ProductUpdateRollbackState
    ) -> ProductUpdateExecutionReport {
        let failedApplyReceipts: [ProductUpdateLayerEffectReceipt] = [
            receipt(
                journal: journal,
                layer: .container,
                operation: .apply,
                state: .succeeded
            ),
            receipt(
                journal: journal,
                layer: .guestRuntime,
                operation: .apply,
                state: .succeeded
            ),
            receipt(
                journal: journal,
                layer: .hostPlatform,
                operation: .apply,
                state: .failed
            ),
        ]
        let successfulRollbackReceipts: [ProductUpdateLayerEffectReceipt] = [
            receipt(
                journal: journal,
                layer: .guestRuntime,
                operation: .rollback,
                state: .succeeded
            ),
            receipt(
                journal: journal,
                layer: .container,
                operation: .rollback,
                state: .succeeded
            ),
        ]
        return ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            requestId: journal.requestId,
            bootstrapEnvelopeId: journal.envelope.id,
            updateSpecificationSHA256:
                journal.envelope.specification.sha256,
            state: state,
            startedAt: "2026-07-29T00:59:00Z",
            finishedAt: "2026-07-29T01:00:00Z",
            applyReceipts: state == .failed ? failedApplyReceipts : [],
            rollbackReceipts: rollback == .succeeded
                ? successfulRollbackReceipts
                : [],
            rollback: rollbackEvidence(rollback),
            failure: state == .failed ? failureIssue() : nil
        )
    }

    private func receipt(
        journal: UpdateBootstrapJournal,
        layer: UpdateLayer,
        operation: ProductUpdateLayerEffectOperation,
        state: ProductUpdateLayerEffectState
    ) -> ProductUpdateLayerEffectReceipt {
        ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            layer: layer,
            effectExecutorId: "\(layer.rawValue)-effect-executor",
            operation: operation,
            artifactSHA256: String(repeating: "d", count: 64),
            state: state,
            observedAt: "2026-07-29T01:00:00Z",
            evidence: ProductUpdateEvidenceReference(
                kind: "layer-effect",
                id: "\(layer.rawValue):\(operation.rawValue)"
            ),
            issue: state == .failed ? failureIssue() : nil
        )
    }

    private func rollbackEvidence(
        _ state: ProductUpdateRollbackState
    ) -> ProductUpdateRollbackEvidence {
        ProductUpdateRollbackEvidence(
            state: state,
            observedAt: "2026-07-29T01:00:00Z",
            evidence: state == .succeeded
                ? ProductUpdateEvidenceReference(
                    kind: "product-update-rollback",
                    id: "update-42:rollback"
                )
                : nil,
            issue: state == .failed
                ? ProductUpdateIssue(
                    code: "rollback-failed",
                    message: "rollback failed",
                    retryable: false,
                    dependency: "effect-executor"
                )
                : nil
        )
    }

    private func failureIssue() -> ProductUpdateIssue {
        ProductUpdateIssue(
            code: "host-effect-failed",
            message: "host effect failed",
            retryable: false,
            dependency: "host-platform-effect-executor"
        )
    }
}
