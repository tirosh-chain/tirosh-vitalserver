import Contracts

public enum RuntimeVitalDBCurrentObservationSource: String, Equatable, Sendable {
    case guestRuntimeState
    case runtimeStatus
}

public struct RuntimeVitalDBCurrentObservationRead: Equatable, Sendable {
    public let source: RuntimeVitalDBCurrentObservationSource?
    public let observation: VitalDBObservationDocument?
    public let readIssues: [String]

    public var readError: String? {
        RuntimeObservabilityReadError.joined(readIssues)
    }

    public init(
        source: RuntimeVitalDBCurrentObservationSource?,
        observation: VitalDBObservationDocument?,
        readIssues: [String]
    ) {
        self.source = source
        self.observation = observation
        self.readIssues = readIssues
    }

    public static func loaded(
        _ observation: VitalDBObservationDocument,
        source: RuntimeVitalDBCurrentObservationSource,
        readIssues: [String] = []
    ) -> RuntimeVitalDBCurrentObservationRead {
        RuntimeVitalDBCurrentObservationRead(
            source: source,
            observation: observation,
            readIssues: readIssues
        )
    }

    public static func unavailable(readIssues: [String] = []) -> RuntimeVitalDBCurrentObservationRead {
        RuntimeVitalDBCurrentObservationRead(
            source: nil,
            observation: nil,
            readIssues: readIssues
        )
    }
}

public enum RuntimeVitalDBProjectedObservationRead: Equatable, Sendable {
    case loaded(VitalDBObservationDocument?)
    case failed(String)
}

public enum RuntimeVitalDBObservationListRead: Equatable, Sendable {
    case loaded([VitalDBObservationDocument])
    case failed(String)
}

public enum RuntimeVitalDBRecorderActivityBucketListRead: Equatable, Sendable {
    case loaded([VitalDBRecorderActivityBucketRecord])
    case failed(String)
}

public struct RuntimeVitalDBRecorderProjectionReads: Equatable, Sendable {
    public let observations: RuntimeVitalDBObservationListRead
    public let currentObservation: RuntimeVitalDBCurrentObservationRead
    public let activityBuckets: RuntimeVitalDBRecorderActivityBucketListRead

    public init(
        observations: RuntimeVitalDBObservationListRead,
        currentObservation: RuntimeVitalDBCurrentObservationRead,
        activityBuckets: RuntimeVitalDBRecorderActivityBucketListRead
    ) {
        self.observations = observations
        self.currentObservation = currentObservation
        self.activityBuckets = activityBuckets
    }
}

public enum RuntimeVitalDBBedAssignmentListRead: Equatable, Sendable {
    case loaded([VitalDBBedAssignmentRecord])
    case failed(String)
}

public enum RuntimeVitalDBRelationshipEventListRead: Equatable, Sendable {
    case loaded([VitalDBRelationshipEventRecord])
    case failed(String)
}

public struct RuntimeVitalDBRelationshipProjectionReads: Equatable, Sendable {
    public let assignments: RuntimeVitalDBBedAssignmentListRead
    public let events: RuntimeVitalDBRelationshipEventListRead

    public init(
        assignments: RuntimeVitalDBBedAssignmentListRead,
        events: RuntimeVitalDBRelationshipEventListRead
    ) {
        self.assignments = assignments
        self.events = events
    }
}

public enum RuntimeVitalDBObservationSnapshotAssembler {
    public static func makeSnapshot(
        currentObservation currentRead: RuntimeVitalDBCurrentObservationRead,
        projectedObservation projectedRead: RuntimeVitalDBProjectedObservationRead
    ) -> RuntimeVitalDBObservationSnapshot {
        switch projectedRead {
        case .loaded(let projectedObservation):
            if let currentObservation = currentRead.observation {
                return RuntimeVitalDBObservationSnapshot(
                    state: .loaded,
                    observation: currentObservation,
                    readError: currentRead.readError
                )
            }
            if let projectedObservation {
                return RuntimeVitalDBObservationSnapshot(
                    state: .loaded,
                    observation: projectedObservation,
                    readError: currentRead.readError
                )
            }
            return RuntimeVitalDBObservationSnapshot.fromOptional(nil, readError: currentRead.readError)
        case .failed(let message):
            let readError = RuntimeObservabilityReadError.joined([
                "projection=\(message)",
                currentRead.readError,
            ])
            if let currentObservation = currentRead.observation {
                return RuntimeVitalDBObservationSnapshot(
                    state: .loaded,
                    observation: currentObservation,
                    readError: readError
                )
            }
            return .failed(readError: readError ?? message)
        }
    }
}

public enum RuntimeVitalDBRecorderHistoryAssembler {
    public static func makeHistory(
        reads: RuntimeVitalDBRecorderProjectionReads
    ) -> RuntimeVitalRecorderHistory {
        var readErrors: [String] = []
        var observations: [VitalDBObservationDocument]

        switch reads.observations {
        case .loaded(let loadedObservations):
            observations = loadedObservations
        case .failed(let message):
            observations = []
            readErrors.append("observations=\(message)")
        }

        if let readError = reads.currentObservation.readError {
            readErrors.append("currentObservation=\(readError)")
        }
        if let currentObservation = reads.currentObservation.observation,
           !observations.contains(where: { $0.observedAt == currentObservation.observedAt }) {
            observations.append(currentObservation)
        }

        let activityBuckets: [VitalDBRecorderActivityBucketRecord]
        let activityHistory: RuntimeVitalRecorderActivityHistory
        switch reads.activityBuckets {
        case .loaded(let loadedActivityBuckets):
            activityBuckets = loadedActivityBuckets
            activityHistory = RuntimeVitalRecorderActivityHistory.fromProjection(
                loadedActivityBuckets,
                readError: RuntimeObservabilityReadError.joined(readErrors)
            )
        case .failed(let message):
            activityBuckets = []
            readErrors.append("activityBuckets=\(message)")
            activityHistory = RuntimeVitalRecorderActivityHistory.unavailable(
                readError: RuntimeObservabilityReadError.joined(readErrors)
            )
        }

        return RuntimeVitalRecorderHistory(
            observations: observations,
            activityBuckets: activityBuckets,
            activityHistory: activityHistory,
            readError: RuntimeObservabilityReadError.joined(readErrors)
        )
    }
}

public enum RuntimeVitalDBRelationshipHistoryAssembler {
    public static func makeHistory(
        reads: RuntimeVitalDBRelationshipProjectionReads
    ) -> RuntimeVitalRelationshipHistory {
        var readErrors: [String] = []
        let assignments: [RuntimeVitalBedAssignmentRecord]
        let events: [RuntimeVitalRelationshipEventRecord]
        let assignmentsReadFailed: Bool
        let eventsReadFailed: Bool

        switch reads.assignments {
        case .loaded(let loadedAssignments):
            assignments = loadedAssignments.map(RuntimeVitalBedAssignmentRecord.init)
            assignmentsReadFailed = false
        case .failed(let message):
            assignments = []
            assignmentsReadFailed = true
            readErrors.append("assignments=\(message)")
        }

        switch reads.events {
        case .loaded(let loadedEvents):
            events = loadedEvents.map(RuntimeVitalRelationshipEventRecord.init)
            eventsReadFailed = false
        case .failed(let message):
            events = []
            eventsReadFailed = true
            readErrors.append("events=\(message)")
        }

        let state: RuntimeVitalRelationshipHistoryState = switch (assignmentsReadFailed, eventsReadFailed) {
        case (false, false):
            .loaded
        case (true, true):
            .readFailed
        case (true, false), (false, true):
            .partiallyLoaded
        }

        return RuntimeVitalRelationshipHistory(
            assignments: assignments,
            events: events,
            state: state,
            readError: RuntimeObservabilityReadError.joined(readErrors)
        )
    }
}

private enum RuntimeObservabilityReadError {
    static func joined(_ parts: [String?]) -> String? {
        joined(parts.compactMap { $0 })
    }

    static func joined(_ parts: [String]) -> String? {
        let messages = parts.filter { !$0.isEmpty }
        guard !messages.isEmpty else {
            return nil
        }
        return messages.joined(separator: ";")
    }
}

private extension RuntimeVitalBedAssignmentRecord {
    init(_ record: VitalDBBedAssignmentRecord) {
        self.init(
            assignmentID: record.id,
            bedID: record.bedID,
            bedName: record.bedName,
            vrcode: record.vrcode,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            lastSeenAt: record.lastSeenAt,
            lastObservedAt: record.lastObservedAt,
            status: RuntimeVitalBedStatus(record.status),
            patientConnected: record.patientConnected,
            observationCount: record.observationCount
        )
    }
}

private extension RuntimeVitalBedStatus {
    init(_ status: VitalDBBedAssignmentStatus) {
        switch status {
        case .online:
            self = .online
        case .stale:
            self = .stale
        case .offline:
            self = .offline
        }
    }
}

private extension RuntimeVitalRelationshipEventRecord {
    init(_ record: VitalDBRelationshipEventRecord) {
        self.init(
            eventID: record.id,
            observedAt: record.observedAt,
            eventType: RuntimeVitalRelationshipEventType(record.eventType),
            severity: RuntimeVitalRelationshipSeverity(record.severity),
            bedID: record.bedID,
            bedName: record.bedName,
            vrcode: record.vrcode,
            previousVrcode: record.previousVrcode,
            previousBedID: record.previousBedID,
            message: record.message
        )
    }
}

private extension RuntimeVitalRelationshipEventType {
    init(_ eventType: VitalDBRelationshipEventType) {
        switch eventType {
        case .handoff:
            self = .handoff
        case .duplicateAssignment:
            self = .duplicateAssignment
        case .unlinkedBed:
            self = .unlinkedBed
        case .unlinkedRecorder:
            self = .unlinkedRecorder
        case .staleLink:
            self = .staleLink
        }
    }
}

private extension RuntimeVitalRelationshipSeverity {
    init(_ severity: VitalDBRelationshipSeverity) {
        switch severity {
        case .info:
            self = .info
        case .warning:
            self = .warning
        case .critical:
            self = .critical
        }
    }
}
