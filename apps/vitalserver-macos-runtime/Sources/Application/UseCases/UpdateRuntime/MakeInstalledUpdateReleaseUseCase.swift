import Contracts
import Domain

public struct MakeInstalledUpdateReleaseUseCase {
    public init() {}

    public func make(
        from journal: UpdateBootstrapJournal
    ) throws -> InstalledUpdateRelease {
        try InstalledUpdateReleasePolicy.make(from: journal)
    }
}
