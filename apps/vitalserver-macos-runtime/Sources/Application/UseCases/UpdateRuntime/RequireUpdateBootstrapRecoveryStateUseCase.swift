import Contracts

public enum UpdateBootstrapRecoveryAction: String, Equatable, Sendable {
    case resumeHandoff = "resume-handoff"
    case settleHandoff = "settle-handoff"
    case failNonTerminal = "fail-non-terminal"
}

public enum RequireUpdateBootstrapRecoveryStateError:
    Error,
    Equatable,
    Sendable
{
    case journalMissing(id: String)
    case journalReadFailed(id: String, reason: String)
    case invalidState(
        id: String,
        action: UpdateBootstrapRecoveryAction,
        expected: [UpdateBootstrapJournalState],
        actual: UpdateBootstrapJournalState
    )
}

public struct RequireUpdateBootstrapRecoveryStateUseCase {
    public init() {}

    public func requireJournal(
        id: String,
        action: UpdateBootstrapRecoveryAction,
        journalRead: UpdateBootstrapJournalReadResult
    ) throws -> UpdateBootstrapJournal {
        let journal: UpdateBootstrapJournal
        switch journalRead {
        case .missing:
            throw RequireUpdateBootstrapRecoveryStateError.journalMissing(
                id: id
            )
        case .failed(let reason):
            throw RequireUpdateBootstrapRecoveryStateError.journalReadFailed(
                id: id,
                reason: reason
            )
        case .loaded(let loaded):
            journal = loaded
        }

        let expected: UpdateBootstrapJournalState
        switch action {
        case .resumeHandoff:
            expected = .handoffPending
        case .settleHandoff:
            expected = .running
        case .failNonTerminal:
            guard [
                UpdateBootstrapJournalState.admitted,
                .handoffPending,
                .running,
            ].contains(journal.state) else {
                throw RequireUpdateBootstrapRecoveryStateError.invalidState(
                    id: id,
                    action: action,
                    expected: [.admitted, .handoffPending, .running],
                    actual: journal.state
                )
            }
            return journal
        }
        guard journal.state == expected else {
            throw RequireUpdateBootstrapRecoveryStateError.invalidState(
                id: id,
                action: action,
                expected: [expected],
                actual: journal.state
            )
        }
        return journal
    }
}
