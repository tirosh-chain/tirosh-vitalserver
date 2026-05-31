import Contracts
import Core

enum RuntimeGuestCapabilityRequirement: String {
    case prepareUpdateShutdown = "prepare-update-shutdown"
    case activateUpdate = "activate-update"
    case redisBackup = "redis-backup"
    case repairDatastore = "repair-datastore"

    func isSupported(by capabilities: GuestRuntimeCapabilities) -> Bool {
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

struct RuntimeGuestCapabilityChecker {
    var loadRuntimeState: () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>

    func require(_ capability: RuntimeGuestCapabilityRequirement) throws {
        switch loadRuntimeState() {
        case .loaded(let state):
            guard let capabilities = state.capabilities,
                  capability.isSupported(by: capabilities)
            else {
                throw LauncherError.runtimeOperationFailed("guest capability missing: \(capability.rawValue)")
            }
        case .missing:
            throw LauncherError.runtimeOperationFailed("guest runtime state missing; cannot confirm guest capability: \(capability.rawValue)")
        case .failed(let message):
            throw LauncherError.runtimeOperationFailed("failed to read guest runtime state for guest capability \(capability.rawValue): \(message)")
        }
    }
}
