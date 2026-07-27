import Contracts

public enum InstalledUpdateReleaseReadResult: Equatable, Sendable {
    case missing
    case loaded(InstalledUpdateRelease)
    case failed(reason: String)
}

public protocol InstalledUpdateReleaseReading: Sendable {
    func loadInstalledUpdateRelease() -> InstalledUpdateReleaseReadResult
}

public protocol SucceededUpdateSettlementWriting: Sendable {
    func settleSucceededUpdate(
        journal: UpdateBootstrapJournal,
        release: InstalledUpdateRelease,
        expectedJournalRevision: Int
    ) throws
}
