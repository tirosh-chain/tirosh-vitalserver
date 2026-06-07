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

public enum RuntimeEventPageState: String, Codable, Equatable, Sendable {
    case loaded
    case partiallyLoaded
    case readFailed
}

public struct RuntimeEventPage: Equatable, Sendable {
    public let state: RuntimeEventPageState
    public let events: [RuntimeEventDocument]
    public let nextCursor: RuntimeEventCursor?
    public let matchingCount: Int?
    public let readError: String?

    public init(
        events: [RuntimeEventDocument],
        nextCursor: RuntimeEventCursor? = nil,
        matchingCount: Int? = nil,
        state: RuntimeEventPageState? = nil,
        readError: String? = nil
    ) {
        self.state = state ?? Self.defaultState(events: events, readError: readError)
        self.events = events
        self.nextCursor = nextCursor
        self.matchingCount = matchingCount
        self.readError = readError
    }

    public static func failed(readError: String) -> RuntimeEventPage {
        RuntimeEventPage(events: [], state: .readFailed, readError: readError)
    }

    private static func defaultState(
        events: [RuntimeEventDocument],
        readError: String?
    ) -> RuntimeEventPageState {
        guard readError != nil else {
            return .loaded
        }
        return events.isEmpty ? .readFailed : .partiallyLoaded
    }
}
