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
    case capabilitiesReadFailed(capability: String, reason: String)

    public var description: String {
        switch self {
        case .missingCapability(let capability):
            return "guest capability missing: \(capability)"
        case .capabilitiesReadFailed(let capability, let reason):
            return "failed to read guest capabilities for \(capability): \(reason)"
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
