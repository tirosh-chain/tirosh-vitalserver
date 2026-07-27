import Contracts
import Domain

public struct ValidateInstalledProductReleaseUseCase {
    public init() {}

    public func validate(_ release: InstalledProductRelease) throws {
        try InstalledProductReleasePolicy.validate(release)
    }
}
