import Contracts
import Domain

public struct ValidateUpdateBootstrapTrustStoreUseCase {
    public init() {}

    public func validate(_ store: UpdateBootstrapTrustStore) throws {
        try UpdateBootstrapTrustStorePolicy.validate(store)
    }
}

public struct ValidateUpdateBootstrapJournalUseCase {
    public init() {}

    public func validate(_ journal: UpdateBootstrapJournal) throws {
        try UpdateBootstrapJournalPolicy.validate(journal)
    }
}
