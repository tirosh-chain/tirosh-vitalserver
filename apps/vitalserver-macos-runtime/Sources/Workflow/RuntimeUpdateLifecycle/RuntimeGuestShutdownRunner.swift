import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestShutdownRunner {
    public var executeShutdownPlan: (RuntimeGuestShutdownExecutionPlan) throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        executeShutdownPlan: @escaping (RuntimeGuestShutdownExecutionPlan) throws -> Void
    ) {
        self.executeShutdownPlan = executeShutdownPlan
    }

    public func prepareForUpdate(version: String) throws {
        try executeShutdownPlan(useCase.guestShutdownExecutionPlan(version: version))
    }
}
