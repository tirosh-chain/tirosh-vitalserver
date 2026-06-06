import Application
import Contracts
import Errors

public struct RuntimeGuestCapabilityChecker {
    public var loadRuntimeState: () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    public var executeRequirementPlan: (RuntimeGuestCapabilityRequirementPlan) throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        loadRuntimeState: @escaping () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>,
        executeRequirementPlan: @escaping (RuntimeGuestCapabilityRequirementPlan) throws -> Void
    ) {
        self.loadRuntimeState = loadRuntimeState
        self.executeRequirementPlan = executeRequirementPlan
    }

    public func require(_ capability: RuntimeGuestCapabilityRequirement) throws {
        try executeRequirementPlan(useCase.guestCapabilityRequirementPlan(
            loadResult: loadRuntimeState(),
            capability: capability
        ))
    }
}
