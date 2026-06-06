import Contracts
import Errors

public struct RuntimeGuestCapabilityChecker {
    public var loadRuntimeState: () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>

    public init(loadRuntimeState: @escaping () -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>) {
        self.loadRuntimeState = loadRuntimeState
    }

    public func require(_ capability: RuntimeGuestCapabilityRequirement) throws {
        switch loadRuntimeState() {
        case .loaded(let state):
            guard let capabilities = state.capabilities,
                  capability.isSupported(by: capabilities)
            else {
                throw RuntimeGuestCapabilityCheckError.missingCapability(capability.rawValue)
            }
        case .missing:
            throw RuntimeGuestCapabilityCheckError.missingRuntimeState(capability.rawValue)
        case .failed(let message):
            throw RuntimeGuestCapabilityCheckError.runtimeStateReadFailed(
                capability: capability.rawValue,
                reason: message
            )
        }
    }
}
