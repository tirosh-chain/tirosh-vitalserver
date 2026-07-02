import Application
import Contracts

public enum RuntimeGuestCapabilityCheckerComposition {
    public static func require(
        _ capability: RuntimeGuestCapabilityRequirement,
        guestControlGateway: RuntimeGuestControlGateway
    ) throws {
        try RequireRuntimeGuestCapabilityUseCase().require(
            capability,
            operations: RuntimeGuestCapabilityRequirementOperations(
                loadCapabilities: {
                    do {
                        return .loaded(try guestControlGateway.capabilities())
                    } catch {
                        return .failed(String(describing: error))
                    }
                }
            )
        )
    }
}
