import Application
import Contracts
import XCTest

final class VerifyUpdateBootstrapCompletionReportUseCaseTests:
    XCTestCase
{
    func testAcceptsReportPathAndDigestOwnedByReceipt() throws {
        let journal = settledRecoveryJournal()

        XCTAssertNoThrow(
            try VerifyUpdateBootstrapCompletionReportUseCase().verify(
                settledJournal: journal,
                reportRead: .loaded(
                    path: "handoff/report.json",
                    sha256: String(repeating: "c", count: 64)
                )
            )
        )
    }

    func testRejectsMissingReportWithoutChangingMeaning() {
        XCTAssertThrowsError(
            try VerifyUpdateBootstrapCompletionReportUseCase().verify(
                settledJournal: settledRecoveryJournal(),
                reportRead: .missing(path: "handoff/report.json")
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapCompletionReportError,
                .reportMissing(path: "handoff/report.json")
            )
        }
    }

    func testRejectsReportDigestMismatch() {
        XCTAssertThrowsError(
            try VerifyUpdateBootstrapCompletionReportUseCase().verify(
                settledJournal: settledRecoveryJournal(),
                reportRead: .loaded(
                    path: "handoff/report.json",
                    sha256: String(repeating: "d", count: 64)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifyUpdateBootstrapCompletionReportError,
                .reportDigestMismatch(
                    expected: String(repeating: "c", count: 64),
                    actual: String(repeating: "d", count: 64)
                )
            )
        }
    }
}

private func settledRecoveryJournal() -> UpdateBootstrapJournal {
    let running = recoveryJournal(state: .running)
    return UpdateBootstrapJournal(
        schemaVersion: running.schemaVersion,
        id: running.id,
        journalRevision: running.journalRevision + 1,
        operationId: running.operationId,
        requestId: running.requestId,
        envelope: running.envelope,
        bootstrapSignedSHA256: running.bootstrapSignedSHA256,
        state: .succeeded,
        stagedUpdaterRelativePath:
            running.stagedUpdaterRelativePath,
        stagedSpecificationRelativePath:
            running.stagedSpecificationRelativePath,
        completion: UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: running.id,
            requestId: running.requestId,
            bootstrapEnvelopeId: running.envelope.id,
            updateSpecificationSHA256:
                running.envelope.specification.sha256,
            expectedJournalRevision: running.journalRevision,
            outcome: .succeeded,
            reportRelativePath: "handoff/report.json",
            reportSHA256: String(repeating: "c", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T02:00:00Z"
        ),
        failureReason: nil,
        createdAt: running.createdAt,
        updatedAt: "2026-07-27T02:00:00Z"
    )
}

