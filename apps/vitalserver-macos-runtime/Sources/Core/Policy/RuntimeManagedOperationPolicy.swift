import Contracts

public enum RuntimeManagedOperationPolicy {
    private static let watchdogProtectedOperations: [RuntimeOperation] = [
        .install,
        .applyBundle,
        .prepareUpdateShutdown,
        .activateGuestUpdate,
        .rollback,
        .redisBackup,
        .repairDatastore,
        .repairVMDisk,
        .startServices,
        .stopServices,
        .uninstall,
    ]

    public static func isProtectedFromWatchdogRecovery(_ operation: RuntimeOperation) -> Bool {
        watchdogProtectedOperations.contains(operation)
    }
}
