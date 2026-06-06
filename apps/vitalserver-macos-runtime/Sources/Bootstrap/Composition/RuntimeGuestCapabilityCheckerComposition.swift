import Application
import Workflow

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
