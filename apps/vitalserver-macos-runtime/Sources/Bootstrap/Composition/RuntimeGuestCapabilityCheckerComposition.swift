import Application
import Contracts

public enum RuntimeGuestCapabilityCheckerComposition {
    public static func require(
        _ capability: RuntimeGuestCapabilityRequirement,
        guestGateway: RuntimeGuestGateway
    ) throws {
        try RequireRuntimeGuestCapabilityUseCase().require(
            capability,
            operations: RuntimeGuestCapabilityRequirementOperations(
                loadRuntimeState: {
                    guestGateway.loadRuntimeStateDocument()
                }
            )
        )
    }
}
