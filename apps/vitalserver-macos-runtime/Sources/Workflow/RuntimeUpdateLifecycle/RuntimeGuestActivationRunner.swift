import Application
import Contracts
import Domain
import Foundation

public struct RuntimeGuestActivationRunner {
    public var executeActivationPlan: (RuntimeGuestActivationExecutionPlan) throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        executeActivationPlan: @escaping (RuntimeGuestActivationExecutionPlan) throws -> Void
    ) {
        self.executeActivationPlan = executeActivationPlan
    }

    public func activateIfNeeded(manifest: UpdateBundleManifest) throws {
        try executeActivationPlan(useCase.guestActivationExecutionPlan(manifest: manifest))
    }
}
