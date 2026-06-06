import Application
import Workflow
import Errors

public enum RuntimeGuestCapabilityCheckerComposition {
    public static func make(
        guestGateway: RuntimeGuestGateway
    ) -> RuntimeGuestCapabilityChecker {
        RuntimeGuestCapabilityChecker(
            loadRuntimeState: {
                guestGateway.loadRuntimeStateDocument()
            },
            executeRequirementPlan: { plan in
                try executeRequirementPlan(plan)
            }
        )
    }

    private static func executeRequirementPlan(_ plan: RuntimeGuestCapabilityRequirementPlan) throws {
        switch plan {
        case .supported:
            return
        case .failed(let failure):
            throw failure
        }
    }
}
