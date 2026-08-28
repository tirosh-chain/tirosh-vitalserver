import Contracts
import Domain

public enum MakeInstalledProductReleaseError: Error, Equatable, Sendable {
    case currentReleaseMissing
    case currentReleaseReadFailed(reason: String)
}

public struct MakeInstalledProductReleaseUseCase {
    public init() {}

    public func makePackageInstall(
        installationId: String,
        productId: String,
        productVersion: String,
        runtimeVersion: String,
        installOperationId: String,
        settledAt: String
    ) throws -> InstalledProductRelease {
        try InstalledProductReleasePolicy.makePackageInstall(
            installationId: installationId,
            productId: productId,
            productVersion: productVersion,
            runtimeVersion: runtimeVersion,
            installOperationId: installOperationId,
            settledAt: settledAt
        )
    }

    public func makeUpdate(
        from journal: UpdateBootstrapJournal,
        currentRelease: InstalledProductReleaseReadResult
    ) throws -> InstalledProductRelease {
        switch currentRelease {
        case .loaded(let current):
            return try InstalledProductReleasePolicy.makeUpdate(
                current: current,
                from: journal
            )
        case .missing:
            throw MakeInstalledProductReleaseError.currentReleaseMissing
        case .failed(let reason):
            throw MakeInstalledProductReleaseError.currentReleaseReadFailed(
                reason: reason
            )
        }
    }
}
