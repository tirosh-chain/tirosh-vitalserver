public enum RuntimeGuestCapabilityRequirement: String, Sendable {
    case prepareUpdateShutdown = "prepare-update-shutdown"
    case activateUpdate = "activate-update"
    case redisBackup = "redis-backup"
    case redisRestore = "redis-restore"
    case repairDatastore = "repair-datastore"

    public var guestControlCapability: String {
        switch self {
        case .prepareUpdateShutdown:
            return "maintenance:update-shutdown:create"
        case .activateUpdate:
            return "maintenance:update-activation:create"
        case .redisBackup:
            return "maintenance:redis-backup:create"
        case .redisRestore:
            return "maintenance:redis-restore:create"
        case .repairDatastore:
            return "maintenance:datastore-repair:create"
        }
    }

    public func isSupported(by capabilities: RuntimeGuestControlCapabilities) -> Bool {
        capabilities.capabilities.contains(guestControlCapability)
    }
}
