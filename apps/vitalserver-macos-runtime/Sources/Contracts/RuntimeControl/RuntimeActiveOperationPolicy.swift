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

    public static func isUpdateInProgress(_ status: PlatformState, operation: RuntimeOperation?) -> Bool {
        guard status.platformHealth != .recovering else {
            return false
        }
        return isUpdateOperation(operation)
    }

    public static func isRecoveryOperation(_ operation: RuntimeOperation?) -> Bool {
        switch operation {
        case .rollback,
             .redisRestore,
             .runtimeDataRestore,
             .repairDatastore,
             .repairVMDisk,
             .repairProxy,
             .repairServices:
            return true
        default:
            return false
        }
    }

    public static func isRecoveryInProgress(_ status: PlatformState, operation: RuntimeOperation?) -> Bool {
        guard status.platformHealth == .recovering else {
            return false
        }
        return isRecoveryOperation(operation) || isUpdateOperation(operation)
    }

    public static func isInitializationInProgress(_ status: PlatformState) -> Bool {
        status.platformHealth == .initializing
    }

    public static func isTerminal(_ phase: RuntimeProgressPhase) -> Bool {
        switch phase {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}
