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
            }
        )
    }
}
