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
        let decision = useCase.guestCapabilityDecision(
            loadResult: loadRuntimeState(),
            capability: capability
        )
        if let failure = decision.failure {
            throw failure
        }
    }
}
