public enum RuntimeGuestCapabilityRequirement: String, Sendable {
    case prepareUpdateShutdown = "prepare-update-shutdown"
    case activateUpdate = "activate-update"
    case redisBackup = "redis-backup"
    case redisRestore = "redis-restore"
    case reconcileCompose = "reconcile-compose"
    case repairDatastore = "repair-datastore"

    public func isSupported(by capabilities: GuestRuntimeCapabilities) -> Bool {
        switch self {
        case .prepareUpdateShutdown:
            return capabilities.prepareUpdateShutdown
        case .activateUpdate:
            return capabilities.activateUpdate
        case .redisBackup:
            return capabilities.redisBackup
        case .redisRestore:
            return capabilities.redisRestore
        case .reconcileCompose:
            return capabilities.reconcileCompose
        case .repairDatastore:
            return capabilities.repairDatastore
        }
    }
}
