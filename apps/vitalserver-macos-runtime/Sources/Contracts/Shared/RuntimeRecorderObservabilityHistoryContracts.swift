import Foundation

public enum RuntimeRecorderObservabilityTimelineState: String, Codable, Equatable, Sendable {
    case loaded
    case notReported
    case unsupported
    case unavailable
}

public enum RuntimeRecorderObservabilityHistorySupportState: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case unknown
}

public enum RuntimeRecorderObservabilityHistoryTimeBasis: String, Codable, Equatable, Sendable {
    case receivedAt
}

public enum RuntimeRecorderObservabilityIncidentPageState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
}

public enum RuntimeRecorderObservabilityIncidentType: String, Codable, Equatable, Sendable {
    case panic
    case oops
    case watchdog
    case lockup
    case unknown
    case bootLoop = "boot-loop"
    case repeatedUndervoltage = "repeated-undervoltage"
    case ledgerContinuity = "ledger-continuity"
}

public struct RuntimeRecorderObservabilityIncidentEvidence: Codable, Equatable, Sendable {
    public let field: String
    public let state: String
    public let detail: String
}

public struct RuntimeRecorderObservabilityTimelineQuery: Equatable, Sendable {
    public let vrcode: String
    public let from: String
    public let until: String
    public let bucketSeconds: Int

    public init(vrcode: String, from: String, until: String, bucketSeconds: Int) {
        self.vrcode = vrcode
        self.from = from
        self.until = until
        self.bucketSeconds = bucketSeconds
    }
}

public struct RuntimeRecorderObservabilityIncidentQuery: Equatable, Sendable {
    public let vrcode: String
    public let from: String
    public let until: String
    public let type: String?
    public let cursor: String?
    public let limit: Int

    public init(
        vrcode: String,
        from: String,
        until: String,
        type: String?,
        cursor: String?,
        limit: Int
    ) {
        self.vrcode = vrcode
        self.from = from
        self.until = until
        self.type = type
        self.cursor = cursor
        self.limit = limit
    }
}

public struct RuntimeRecorderObservabilityMetricBucket: Codable, Equatable, Sendable {
    public let average: Double?
    public let stateCounts: [String: Int]
}

public struct RuntimeRecorderObservabilityTimelineBucket: Codable, Equatable, Sendable {
    public let bucketStartedAt: String
    public let sampleCount: Int
    public let metrics: [String: RuntimeRecorderObservabilityMetricBucket]
}

public struct RuntimeRecorderObservabilityTimeline: Codable, Equatable, Sendable {
    public struct Query: Codable, Equatable, Sendable {
        public let from: String
        public let until: String
        public let bucketSeconds: Int
    }

    public let state: RuntimeRecorderObservabilityTimelineState
    public let vrcode: String
    public let supportState: RuntimeRecorderObservabilityHistorySupportState?
    public let timeBasis: RuntimeRecorderObservabilityHistoryTimeBasis
    public let query: Query?
    public let buckets: [RuntimeRecorderObservabilityTimelineBucket]
    public let readError: String?

    public static func unavailable(vrcode: String, readError: String) -> Self {
        .init(
            state: .unavailable,
            vrcode: vrcode,
            supportState: nil,
            timeBasis: .receivedAt,
            query: nil,
            buckets: [],
            readError: readError
        )
    }
}

public struct RuntimeRecorderObservabilityIncident: Codable, Equatable, Sendable {
    public let incidentId: String
    public let recordId: String
    public let eventId: String
    public let category: String
    public let code: String
    public let severity: String
    public let state: String
    public let bootId: String?
    public let occurredAt: String?
    public let receivedAt: String
    public let timeState: String
    public let summary: String
    public let evidence: [RuntimeRecorderObservabilityIncidentEvidence]
    public let source: String
    public let capturedAt: String?
    public let captureTimeState: String?
    public let incidentType: RuntimeRecorderObservabilityIncidentType
    public let incidentBootId: String?
    public let messageExcerpt: String?
    public let truncated: Bool
}

public struct RuntimeRecorderObservabilityIncidents: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityIncidentPageState
    public let vrcode: String
    public let timeBasis: RuntimeRecorderObservabilityHistoryTimeBasis
    public let incidents: [RuntimeRecorderObservabilityIncident]
    public let nextCursor: String?
    public let readError: String?

    public static func unavailable(vrcode: String, readError: String) -> Self {
        .init(
            state: .unavailable,
            vrcode: vrcode,
            timeBasis: .receivedAt,
            incidents: [],
            nextCursor: nil,
            readError: readError
        )
    }
}
