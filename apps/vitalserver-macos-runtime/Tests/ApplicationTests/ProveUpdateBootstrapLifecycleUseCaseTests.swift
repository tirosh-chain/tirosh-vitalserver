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
        ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            requestId: journal.requestId,
            bootstrapEnvelopeId: journal.envelope.id,
            updateSpecificationSHA256:
                journal.envelope.specification.sha256,
            state: state,
            startedAt: "2026-07-29T00:59:00Z",
            finishedAt: "2026-07-29T01:00:00Z",
            applyReceipts: [],
            rollbackReceipts: [],
            rollback: ProductUpdateRollbackEvidence(
                state: rollback,
                observedAt: "2026-07-29T01:00:00Z",
                evidence: rollback == .succeeded
                    ? ProductUpdateEvidenceReference(
                        kind: "product-update-rollback",
                        id: "\(journal.id):rollback"
                    )
                    : nil,
                issue: rollback == .failed
                    ? ProductUpdateIssue(
                        code: "rollback-failed",
                        message: "rollback failed",
                        retryable: false,
                        dependency: "effect-executor"
                    )
                    : nil
            ),
            failure: state == .failed
                ? ProductUpdateIssue(
                    code: "host-effect-failed",
                    message: "host effect failed",
                    retryable: false,
                    dependency: "host-platform-effect-executor"
                )
                : nil
        )
    }
}
