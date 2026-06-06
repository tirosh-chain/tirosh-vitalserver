import Contracts
import RuntimeControl
import Errors

public struct RuntimeActiveOperationPolicy {
    public static func isUpdateOperation(_ operation: RuntimeOperation?) -> Bool {
        switch operation {
        case .applyBundle, .prepareUpdateShutdown, .activateGuestUpdate:
            return true
        default:
            return false
        }
    }

    public static func isUpdateInProgress(_ status: RuntimeStatus) -> Bool {
        if let progress = status.progress,
           isUpdateOperation(progress.operation),
           !isTerminal(progress.phase) {
            return true
        }
        guard isUpdateOperation(status.operation) else {
            return false
        }
        return status.runtimeState == .updating || status.runtimeState == .recovering
    }

    private static func isTerminal(_ phase: RuntimeProgressPhase) -> Bool {
        switch phase {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}
