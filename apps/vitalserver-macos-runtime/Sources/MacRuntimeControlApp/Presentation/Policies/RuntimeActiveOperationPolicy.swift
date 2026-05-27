import Contracts
import RuntimeControl

struct RuntimeActiveOperationPolicy {
    static func isUpdateOperation(_ operation: RuntimeOperation?) -> Bool {
        switch operation {
        case .applyBundle, .activateGuestUpdate:
            return true
        default:
            return false
        }
    }

    static func isUpdateInProgress(_ status: RuntimeStatus) -> Bool {
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
