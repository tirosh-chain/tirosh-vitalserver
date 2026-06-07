public struct RuntimeOperationLeaseDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let operationId: String
    public let operation: RuntimeOperation
    public let ownerPID: Int?
    public let startedAt: String
    public let heartbeatAt: String
    public let expiresAt: String?
    public let message: String?

    public init(
        schemaVersion: Int = 1,
        operationId: String,
        operation: RuntimeOperation,
        ownerPID: Int?,
        startedAt: String,
        heartbeatAt: String,
        expiresAt: String?,
        message: String?
    ) {
        self.schemaVersion = schemaVersion
        self.operationId = operationId
        self.operation = operation
        self.ownerPID = ownerPID
        self.startedAt = startedAt
        self.heartbeatAt = heartbeatAt
        self.expiresAt = expiresAt
        self.message = message
    }
}
