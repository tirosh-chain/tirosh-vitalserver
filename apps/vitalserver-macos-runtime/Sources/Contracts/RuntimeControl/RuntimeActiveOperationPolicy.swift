import Contracts
import Errors

public enum RuntimeActiveOperationPolicy {
    public static func isInstallOperation(_ operation: RuntimeOperation?) -> Bool {
        switch operation {
        case .install:
            return true
        default:
            return false
        }
    }

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
           isUpdateOperation(progress.operation) {
            return !isTerminal(progress.phase)
        }
        guard isUpdateOperation(status.operation) else {
            return false
        }
        return status.runtimeState == .updating || status.runtimeState == .recovering
    }

    public static func isInstallInProgress(_ status: RuntimeStatus) -> Bool {
        if let progress = status.progress,
           isInstallOperation(progress.operation) {
            return !isTerminal(progress.phase)
        }
        if let installState = status.installStateDocument?.state {
            return isInstallStateInProgress(installState, status: status)
        }
        guard isInstallOperation(status.operation) else {
            return status.runtimeState == .installing
        }
        return status.runtimeState == .installing || status.runtimeState == .degraded
    }

    public static func isTerminal(_ phase: RuntimeProgressPhase) -> Bool {
        switch phase {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    private static func isInstallStateInProgress(_ state: RuntimeInstallState, status: RuntimeStatus) -> Bool {
        switch state {
        case .preflightBlocked, .provisionPayloadBlocked, .completed, .failed:
            return false
        case .started,
             .settingsLoaded,
             .preflightVerified,
             .provisionPayloadVerified,
             .stepStarted,
             .stepCompleted,
             .unknown:
            return true
        case .provisioned:
            return !RuntimeReadinessPolicy.isReady(status)
        }
    }
}
