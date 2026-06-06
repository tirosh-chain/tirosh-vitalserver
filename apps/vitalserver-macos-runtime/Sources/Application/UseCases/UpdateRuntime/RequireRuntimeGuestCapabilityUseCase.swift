import Contracts
import Errors

public struct RuntimeGuestCapabilityRequirementOperations {
    public let loadRuntimeState: () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>

    public init(
        loadRuntimeState: @escaping () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    ) {
        self.loadRuntimeState = loadRuntimeState
    }
}

public struct RequireRuntimeGuestCapabilityUseCase {
    public init() {}

    public func require(
        _ capability: RuntimeGuestCapabilityRequirement,
        operations: RuntimeGuestCapabilityRequirementOperations
    ) throws {
        let plan = UpdateRuntimeUseCase().guestCapabilityRequirementPlan(
            loadResult: operations.loadRuntimeState(),
            capability: capability
        )
        switch plan {
        case .supported:
            return
        case .failed(let failure):
            throw failure
        }
    }
}
