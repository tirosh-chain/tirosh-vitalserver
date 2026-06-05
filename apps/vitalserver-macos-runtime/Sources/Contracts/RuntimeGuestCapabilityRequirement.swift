public enum RuntimeGuestCapabilityRequirement: String {
    case prepareUpdateShutdown = "prepare-update-shutdown"
    case activateUpdate = "activate-update"
    case redisBackup = "redis-backup"
    case repairDatastore = "repair-datastore"

    public func isSupported(by capabilities: GuestRuntimeCapabilities) -> Bool {
        switch self {
        case .prepareUpdateShutdown:
            return capabilities.prepareUpdateShutdown
        case .activateUpdate:
            return capabilities.activateUpdate
        case .redisBackup:
            return capabilities.redisBackup
        case .repairDatastore:
            return capabilities.repairDatastore
        }
    }
}
