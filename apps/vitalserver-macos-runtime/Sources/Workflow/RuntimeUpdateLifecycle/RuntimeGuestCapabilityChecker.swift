import Contracts

public enum RuntimeGuestCapabilityCheckError: Error, CustomStringConvertible, Equatable {
    case missingCapability(String)
    case missingRuntimeState(String)
    case runtimeStateReadFailed(capability: String, reason: String)

    public var description: String {
        switch self {
        case .missingCapability(let capability):
            return "guest capability missing: \(capability)"
        case .missingRuntimeState(let capability):
            return "guest runtime state missing; cannot confirm guest capability: \(capability)"
        case .runtimeStateReadFailed(let capability, let reason):
            return "failed to read guest runtime state for guest capability \(capability): \(reason)"
        }
    }
}

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
