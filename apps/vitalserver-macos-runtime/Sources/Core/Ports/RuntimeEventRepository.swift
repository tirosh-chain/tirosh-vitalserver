import Contracts

public struct RuntimeEventCursor: Codable, Equatable, Sendable {
    public let timestamp: String
    public let id: String

    public init(timestamp: String, id: String) {
        self.timestamp = timestamp
        self.id = id
    }
}

public struct RuntimeEventQuery: Equatable, Sendable {
    public static let defaultLimit = 100
    public static let maximumLimit = 500

    public let limit: Int
    public let eventType: RuntimeEventType?
    public let since: String?
    public let before: RuntimeEventCursor?

    public init(
        limit: Int = defaultLimit,
        eventType: RuntimeEventType? = nil,
        since: String? = nil,
        before: RuntimeEventCursor? = nil
    ) {
        self.limit = min(max(limit, 1), Self.maximumLimit)
        self.eventType = eventType
        self.since = since
        self.before = before
    }
}

public struct RuntimeEventPage: Equatable, Sendable {
    public let events: [RuntimeEventDocument]
    public let nextCursor: RuntimeEventCursor?
    public let matchingCount: Int?

    public init(
        events: [RuntimeEventDocument],
        nextCursor: RuntimeEventCursor? = nil,
        matchingCount: Int? = nil
    ) {
        self.events = events
        self.nextCursor = nextCursor
        self.matchingCount = matchingCount
    }
}

public protocol RuntimeEventRecording {
    func append(_ event: RuntimeEventDocument) throws
}

public protocol RuntimeEventHistoryReading {
    func query(_ query: RuntimeEventQuery) -> RuntimeEventPage
}

public protocol RuntimeEventRepository {
    func append(_ event: RuntimeEventDocument) throws
    func recent(limit: Int) -> [RuntimeEventDocument]
}
