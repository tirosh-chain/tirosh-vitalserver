import Contracts

public struct UpdateRuntimeStatusPlan: Equatable, Sendable {
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

public struct UpdateRuntimeLoggedStatusPlan: Equatable, Sendable {
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
