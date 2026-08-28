import Contracts

public enum UpdateBootstrapJournalReadResult: Equatable, Sendable {
    case missing
    case loaded(UpdateBootstrapJournal)
    case failed(reason: String)
}

public protocol UpdateBootstrapJournalReading: Sendable {
    func loadUpdateBootstrapJournal(id: String) -> UpdateBootstrapJournalReadResult
    func loadLatestUpdateBootstrapJournal() -> UpdateBootstrapJournalReadResult
}

public protocol UpdateBootstrapJournalWriting: Sendable {
    func saveUpdateBootstrapJournal(
        _ journal: UpdateBootstrapJournal,
        expectedRevision: Int?
    ) throws
}

public protocol UpdateBootstrapJournalRepository:
    UpdateBootstrapJournalReading,
    UpdateBootstrapJournalWriting
{}
