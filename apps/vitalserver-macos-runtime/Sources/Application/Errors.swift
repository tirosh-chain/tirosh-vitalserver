import Foundation


public enum ApplyRuntimeBundleCompositionError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}


public enum ConfigureRuntimeError: Error, Equatable {
    case invalidArgument(String)
}


public enum InstallRuntimeUseCaseError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}


public enum RefreshRuntimeHealthUseCaseError: Error, Equatable, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}


public enum RepairRuntimeUseCaseError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}


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


public enum RuntimeGuestUpdateUseCaseError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}


public enum RuntimeServiceControlError: Error, Equatable {
    case operationFailed(String)
}


public enum UninstallRuntimeUseCaseError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}
