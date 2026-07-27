import Contracts

public enum InstalledProductReleaseReadResult: Equatable, Sendable {
    case missing
    case loaded(InstalledProductRelease)
    case failed(reason: String)
}

public protocol InstalledProductReleaseReading: Sendable {
    func loadInstalledProductRelease() -> InstalledProductReleaseReadResult
}

public protocol PackageInstallReleaseWriting: Sendable {
    func settlePackageInstallRelease(_ release: InstalledProductRelease) throws
}

public protocol SucceededUpdateSettlementWriting: Sendable {
    func settleSucceededUpdate(
        journal: UpdateBootstrapJournal,
        release: InstalledProductRelease,
        expectedJournalRevision: Int,
        expectedReleaseRevision: Int
    ) throws
}
