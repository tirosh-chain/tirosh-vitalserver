public enum RuntimeOperationEventType: String, Codable, CaseIterable, Equatable, Sendable {
    case accepted = "operation-accepted"
    case running = "operation-running"
    case completed = "operation-completed"
    case failed = "operation-failed"
    case cancelled = "operation-cancelled"
    case interrupted = "operation-interrupted"
}

public struct RuntimeOperationEventDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let source: String
    public let eventType: RuntimeOperationEventType
    public let timestamp: String
    public let operationId: String
    public let operationService: String
    public let operationCommand: String
    public let operationState: RuntimeGuestControlOperationState
    public let message: String
    public let failure: RuntimeGuestControlOperationFailure?

    public init(
        schemaVersion: Int,
        id: String,
        source: String,
        eventType: RuntimeOperationEventType,
        timestamp: String,
        operationId: String,
        operationService: String,
        operationCommand: String,
        operationState: RuntimeGuestControlOperationState,
        message: String,
        failure: RuntimeGuestControlOperationFailure?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.source = source
        self.eventType = eventType
        self.timestamp = timestamp
        self.operationId = operationId
        self.operationService = operationService
        self.operationCommand = operationCommand
        self.operationState = operationState
        self.message = message
        self.failure = failure
    }
}

public struct RuntimeOperationEventHistory: Codable, Equatable, Sendable {
    public let events: [RuntimeOperationEventDocument]
    public let nextCursor: String?
    public let matchingCount: Int?

    public init(
        events: [RuntimeOperationEventDocument],
        nextCursor: String?,
        matchingCount: Int?
    ) {
        self.events = events
        self.nextCursor = nextCursor
        self.matchingCount = matchingCount
    }

    private enum CodingKeys: String, CodingKey {
        case events
        case nextCursor
        case matchingCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([RuntimeOperationEventDocument].self, forKey: .events)
        guard container.contains(.nextCursor) else {
            throw DecodingError.keyNotFound(
                CodingKeys.nextCursor,
                DecodingError.Context(
                    codingPath: [CodingKeys.nextCursor],
                    debugDescription: "Runtime operation event history requires explicit nextCursor"
                )
            )
        }
        guard container.contains(.matchingCount) else {
            throw DecodingError.keyNotFound(
                CodingKeys.matchingCount,
                DecodingError.Context(
                    codingPath: [CodingKeys.matchingCount],
                    debugDescription: "Runtime operation event history requires explicit matchingCount"
                )
            )
        }
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        matchingCount = try container.decodeIfPresent(Int.self, forKey: .matchingCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        if let matchingCount {
            try container.encode(matchingCount, forKey: .matchingCount)
        } else {
            try container.encodeNil(forKey: .matchingCount)
        }
    }
}
