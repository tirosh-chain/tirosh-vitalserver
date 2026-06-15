import Contracts
import Domain

public struct MakeUpdateBundleVerificationPlanUseCase {
    public init() {}

    public func makePlan(
        manifest: UpdateBundleManifest,
        expectedProduct: String
    ) throws -> UpdateBundleVerificationPlan {
        try UpdateBundleVerifier.makePlan(
            manifest: manifest,
            expectedProduct: expectedProduct
        )
    }
}
