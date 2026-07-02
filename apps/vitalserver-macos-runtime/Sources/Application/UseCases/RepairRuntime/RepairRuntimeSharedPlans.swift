import Contracts

public struct RepairRuntimeStatusPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let message: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) {
        self.status = status
        self.operation = operation
        self.message = message
    }
}

public struct RepairRuntimeLoggedStatusPlan: Equatable, Sendable {
    public let logMessage: String
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String

    public init(
        logMessage: String,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String
    ) {
        self.logMessage = logMessage
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
    }
}

public struct RepairRuntimeFailureStatusPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String
    public let failureMessage: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String,
        failureMessage: String
    ) {
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
        self.failureMessage = failureMessage
    }
}
