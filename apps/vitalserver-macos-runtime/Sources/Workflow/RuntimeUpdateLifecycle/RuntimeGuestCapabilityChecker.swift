import Application
import Contracts
import Errors

public struct RuntimeGuestCapabilityChecker {
    public var loadRuntimeState: () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(loadRuntimeState: @escaping () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>) {
        self.loadRuntimeState = loadRuntimeState
    }

    public func require(_ capability: RuntimeGuestCapabilityRequirement) throws {
        switch useCase.guestCapabilityRequirementPlan(
            loadResult: loadRuntimeState(),
            capability: capability
        ) {
        case .supported:
            return
        case .failed(let failure):
            throw failure
        }
    }
}
