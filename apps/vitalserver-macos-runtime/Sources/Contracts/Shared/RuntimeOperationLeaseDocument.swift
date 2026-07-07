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

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case operationId
        case operation
        case ownerPID
        case startedAt
        case heartbeatAt
        case expiresAt
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.operationId = try container.decode(String.self, forKey: .operationId)
        self.operation = try container.decode(RuntimeOperation.self, forKey: .operation)
        self.ownerPID = try container.decodeIfPresent(Int.self, forKey: .ownerPID)
        self.startedAt = try container.decode(String.self, forKey: .startedAt)
        self.heartbeatAt = try container.decode(String.self, forKey: .heartbeatAt)
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(operation, forKey: .operation)
        if let ownerPID {
            try container.encode(ownerPID, forKey: .ownerPID)
        } else {
            try container.encodeNil(forKey: .ownerPID)
        }
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(heartbeatAt, forKey: .heartbeatAt)
        if let expiresAt {
            try container.encode(expiresAt, forKey: .expiresAt)
        } else {
            try container.encodeNil(forKey: .expiresAt)
        }
        if let message {
            try container.encode(message, forKey: .message)
        } else {
            try container.encodeNil(forKey: .message)
        }
    }
}
