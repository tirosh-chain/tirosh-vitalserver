public enum RuntimeVitalBedStatus: String, Codable, Equatable, Sendable {
    case online
    case stale
    case offline
    case notObserved
    case unknown
}

public enum RuntimeVitalRelationshipEventType: String, Codable, Equatable, Sendable {
    case handoff
    case duplicateAssignment
    case unlinkedBed
    case unlinkedRecorder
    case staleLink
}

public enum RuntimeVitalRelationshipSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case critical
}

public struct RuntimeVitalBedAssignmentRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { assignmentID }
    public let assignmentID: String
    public let bedID: String
    public let bedName: String?
    public let vrcode: String
    public let startedAt: String
    public let endedAt: String?
    public let lastSeenAt: String?
    public let lastObservedAt: String
    public let status: RuntimeVitalBedStatus
    public let patientConnected: Bool?
    public let observationCount: Int

    public init(
        assignmentID: String,
        bedID: String,
        bedName: String?,
        vrcode: String,
        startedAt: String,
        endedAt: String?,
        lastSeenAt: String?,
        lastObservedAt: String,
        status: RuntimeVitalBedStatus,
        patientConnected: Bool?,
        observationCount: Int
    ) {
        self.assignmentID = assignmentID
        self.bedID = bedID
        self.bedName = bedName
        self.vrcode = vrcode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastSeenAt = lastSeenAt
        self.lastObservedAt = lastObservedAt
        self.status = status
        self.patientConnected = patientConnected
        self.observationCount = observationCount
    }
}

public struct RuntimeVitalRelationshipEventRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { eventID }
    public let eventID: String
    public let observedAt: String
    public let eventType: RuntimeVitalRelationshipEventType
    public let severity: RuntimeVitalRelationshipSeverity
    public let bedID: String?
    public let bedName: String?
    public let vrcode: String?
    public let previousVrcode: String?
    public let previousBedID: String?
    public let message: String

    public init(
        eventID: String,
        observedAt: String,
        eventType: RuntimeVitalRelationshipEventType,
        severity: RuntimeVitalRelationshipSeverity,
        bedID: String?,
        bedName: String?,
        vrcode: String?,
        previousVrcode: String?,
        previousBedID: String?,
        message: String
    ) {
        self.eventID = eventID
        self.observedAt = observedAt
        self.eventType = eventType
        self.severity = severity
        self.bedID = bedID
        self.bedName = bedName
        self.vrcode = vrcode
        self.previousVrcode = previousVrcode
        self.previousBedID = previousBedID
        self.message = message
    }
}

public enum RuntimeVitalRelationshipHistoryState: String, Codable, Equatable, Sendable {
    case loaded
    case partiallyLoaded
    case readFailed
}

public struct RuntimeVitalRelationshipHistory: Codable, Equatable, Sendable {
    public let state: RuntimeVitalRelationshipHistoryState
    public let assignments: [RuntimeVitalBedAssignmentRecord]
    public let events: [RuntimeVitalRelationshipEventRecord]
    public let readError: String?

    public init(
        assignments: [RuntimeVitalBedAssignmentRecord] = [],
        events: [RuntimeVitalRelationshipEventRecord] = [],
        state: RuntimeVitalRelationshipHistoryState? = nil,
        readError: String? = nil
    ) {
        self.state = state ?? Self.defaultState(
            assignments: assignments,
            events: events,
            readError: readError
        )
        self.assignments = assignments
        self.events = events
        self.readError = readError
    }

    public static func failed(readError: String) -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory(
            state: .readFailed,
            readError: readError
        )
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case assignments
        case events
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try container.decodeIfPresent([RuntimeVitalBedAssignmentRecord].self, forKey: .assignments) ?? []
        events = try container.decodeIfPresent([RuntimeVitalRelationshipEventRecord].self, forKey: .events) ?? []
        readError = try container.decodeIfPresent(String.self, forKey: .readError)
        state = try container.decodeIfPresent(RuntimeVitalRelationshipHistoryState.self, forKey: .state)
            ?? Self.defaultState(
                assignments: assignments,
                events: events,
                readError: readError
            )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(readError, forKey: .readError)
    }

    private static func defaultState(
        assignments: [RuntimeVitalBedAssignmentRecord],
        events: [RuntimeVitalRelationshipEventRecord],
        readError: String?
    ) -> RuntimeVitalRelationshipHistoryState {
        guard readError != nil else {
            return .loaded
        }
        return assignments.isEmpty && events.isEmpty ? .readFailed : .partiallyLoaded
    }
}
