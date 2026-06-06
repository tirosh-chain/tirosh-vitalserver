import Foundation

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
