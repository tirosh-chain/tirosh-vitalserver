import Foundation

public enum VitalDBRelationshipEventType: String, Codable, Equatable, Sendable {
    case handoff
    case duplicateAssignment
    case unlinkedBed
    case unlinkedRecorder
    case staleLink
}

public enum VitalDBRelationshipSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case critical
}

public struct VitalDBBedAssignmentRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public let bedID: String
    public let bedName: String?
    public let vrcode: String
    public let startedAt: String
    public let endedAt: String?
    public let lastSeenAt: String?
    public let lastObservedAt: String
    public let status: String
    public let patientConnected: Bool?
    public let observationCount: Int

    public init(
        id: String,
        bedID: String,
        bedName: String?,
        vrcode: String,
        startedAt: String,
        endedAt: String?,
        lastSeenAt: String?,
        lastObservedAt: String,
        status: String,
        patientConnected: Bool?,
        observationCount: Int
    ) {
        self.id = id
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

public struct VitalDBRelationshipEventRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public let observedAt: String
    public let eventType: VitalDBRelationshipEventType
    public let severity: VitalDBRelationshipSeverity
    public let bedID: String?
    public let bedName: String?
    public let vrcode: String?
    public let previousVrcode: String?
    public let previousBedID: String?
    public let message: String

    public init(
        id: String,
        observedAt: String,
        eventType: VitalDBRelationshipEventType,
        severity: VitalDBRelationshipSeverity,
        bedID: String?,
        bedName: String?,
        vrcode: String?,
        previousVrcode: String?,
        previousBedID: String?,
        message: String
    ) {
        self.id = id
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
