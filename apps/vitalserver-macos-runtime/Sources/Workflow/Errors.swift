import Contracts
import Foundation


public enum RollbackRuntimeUseCaseError: Error, Equatable, CustomStringConvertible, LocalizedError {
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


public enum RuntimeHealthWaitRunnerError: Error, CustomStringConvertible, Equatable {
    case runtimeHealthFailed

    public var description: String {
        switch self {
        case .runtimeHealthFailed:
            return "runtime health check failed"
        }
    }
}


public enum RuntimeHealthWaitUseCaseError: Error, Equatable, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}


public struct RuntimeInstallStepExecutionError: Error, Equatable, CustomStringConvertible {
    public let step: RuntimeWorkflowStep?
    public let message: String

    public init(step: RuntimeWorkflowStep) {
        self.step = step
        self.message = "unsupported command: install step \(step.rawValue)"
    }

    public init(_ message: String) {
        self.step = nil
        self.message = message
    }

    public var description: String {
        message
    }
}

public struct RuntimeUninstallFileRemovalExecutionError: Error {
    public let underlyingError: Error
    public let blockers: [String]

    public init(underlyingError: Error, blockers: [String]) {
        self.underlyingError = underlyingError
        self.blockers = blockers
    }
}

public struct RuntimeUninstallReceiptForgetExecutionError: Error, Equatable {
    public let identifier: String
    public let reason: String

    public init(identifier: String, reason: String) {
        self.identifier = identifier
        self.reason = reason
    }
}
