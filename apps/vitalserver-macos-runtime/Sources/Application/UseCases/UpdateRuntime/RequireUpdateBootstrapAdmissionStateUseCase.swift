import Contracts

public enum RequireUpdateBootstrapAdmissionStateError:
    Error,
    Equatable,
    Sendable
{
    case installedReleaseMissing
    case installedReleaseReadFailed(reason: String)
    case journalAlreadyExists(
        id: String,
        state: UpdateBootstrapJournalState,
        requestId: String
    )
    case journalReadFailed(id: String, reason: String)
}

public struct RequireUpdateBootstrapAdmissionStateUseCase {
    public init() {}

    public func requireNewAdmission(
        installedRelease: InstalledProductReleaseReadResult,
        journalId: String,
        journal: UpdateBootstrapJournalReadResult
    ) throws -> InstalledProductRelease {
        let release: InstalledProductRelease
        switch installedRelease {
        case .loaded(let value):
            release = value
        case .missing:
            throw RequireUpdateBootstrapAdmissionStateError
                .installedReleaseMissing
        case .failed(let reason):
            throw RequireUpdateBootstrapAdmissionStateError
                .installedReleaseReadFailed(reason: reason)
        }

        switch journal {
        case .missing:
            return release
        case .loaded(let value):
            throw RequireUpdateBootstrapAdmissionStateError
                .journalAlreadyExists(
                    id: value.id,
                    state: value.state,
                    requestId: value.requestId
                )
        case .failed(let reason):
            throw RequireUpdateBootstrapAdmissionStateError.journalReadFailed(
                id: journalId,
                reason: reason
            )
        }
    }
}
