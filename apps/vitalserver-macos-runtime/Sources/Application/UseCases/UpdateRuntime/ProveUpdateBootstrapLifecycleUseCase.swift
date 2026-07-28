import Contracts

public enum UpdateBootstrapLifecycleProofExpectation:
    String,
    Equatable,
    Sendable
{
    case succeeded
    case failedRolledBack = "failed-rolled-back"
}

public enum ProveUpdateBootstrapLifecycleError:
    Error,
    Equatable,
    Sendable
{
    case journalMissing(id: String)
    case journalReadFailed(id: String, reason: String)
    case journalIdentityMismatch(expected: String, actual: String)
    case completionMissing(id: String)
    case reportCorrelationMismatch
    case expectedSuccess(
        journalState: UpdateBootstrapJournalState,
        completionOutcome: UpdateBootstrapCompletionOutcome,
        reportState: ProductUpdateExecutionState
    )
    case expectedFailedRollback(
        journalState: UpdateBootstrapJournalState,
        completionOutcome: UpdateBootstrapCompletionOutcome,
        reportState: ProductUpdateExecutionState,
        rollbackState: ProductUpdateRollbackState
    )
}

public struct ProveUpdateBootstrapLifecycleUseCase {
    public init() {}

    public func execute(
        expectation: UpdateBootstrapLifecycleProofExpectation,
        journal: UpdateBootstrapJournal,
        report: ProductUpdateExecutionReport
    ) throws -> UpdateBootstrapJournal {
        guard let completion = journal.completion else {
            throw ProveUpdateBootstrapLifecycleError.completionMissing(
                id: journal.id
            )
        }
        guard report.updateId == journal.id,
              report.requestId == journal.requestId,
              report.bootstrapEnvelopeId == journal.envelope.id,
              report.updateSpecificationSHA256
                == journal.envelope.specification.sha256 else {
            throw ProveUpdateBootstrapLifecycleError
                .reportCorrelationMismatch
        }

        switch expectation {
        case .succeeded:
            guard journal.state == .succeeded,
                  completion.outcome == .succeeded,
                  report.state == .succeeded else {
                throw ProveUpdateBootstrapLifecycleError.expectedSuccess(
                    journalState: journal.state,
                    completionOutcome: completion.outcome,
                    reportState: report.state
                )
            }
        case .failedRolledBack:
            guard journal.state == .failed,
                  completion.outcome == .failed,
                  report.state == .failed,
                  report.rollback.state == .succeeded else {
                throw ProveUpdateBootstrapLifecycleError
                    .expectedFailedRollback(
                        journalState: journal.state,
                        completionOutcome: completion.outcome,
                        reportState: report.state,
                        rollbackState: report.rollback.state
                    )
            }
        }
        return journal
    }

    public func requireJournal(
        updateId: String,
        journalRead: UpdateBootstrapJournalReadResult
    ) throws -> UpdateBootstrapJournal {
        let journal: UpdateBootstrapJournal
        switch journalRead {
        case .missing:
            throw ProveUpdateBootstrapLifecycleError.journalMissing(
                id: updateId
            )
        case .failed(let reason):
            throw ProveUpdateBootstrapLifecycleError.journalReadFailed(
                id: updateId,
                reason: reason
            )
        case .loaded(let loaded):
            journal = loaded
        }
        guard journal.id == updateId else {
            throw ProveUpdateBootstrapLifecycleError
                .journalIdentityMismatch(
                    expected: updateId,
                    actual: journal.id
                )
        }
        return journal
    }
}
