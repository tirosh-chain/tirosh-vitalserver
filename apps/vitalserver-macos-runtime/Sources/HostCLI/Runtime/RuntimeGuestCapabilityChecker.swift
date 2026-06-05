import Contracts
import Core

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
