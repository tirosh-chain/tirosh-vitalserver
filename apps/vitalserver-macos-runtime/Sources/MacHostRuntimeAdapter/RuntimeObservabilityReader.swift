import Contracts
import Foundation
import HostInfrastructure
import RuntimeControl

protocol RuntimeObservabilityReading: Sendable {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservation() -> VitalDBObservationDocument?
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
}

extension RuntimeObservabilityReading {
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(loadVitalDBObservation())
    }
}

struct SystemRuntimeObservabilityReader: RuntimeObservabilityReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let statusObservationProvider: (@Sendable () -> VitalDBObservationDocument?)?

    init(
        paths: RuntimePaths,
        statusObservationProvider: (@Sendable () -> VitalDBObservationDocument?)? = nil
    ) {
        self.paths = paths
        self.statusObservationProvider = statusObservationProvider
    }

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEvents(query: RuntimeEventQuery(limit: limit))
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        let primary = JSONLRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeEvents))
        let secondary = SQLiteRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeObservabilityDB))
        RuntimeEventSQLiteProjectionCatchUp(primary: primary, secondary: secondary).catchUpIfDue()
        let repository = CompositeRuntimeEventRepository(primary: primary, secondary: secondary)
        let page = repository.query(query)
        return RuntimeEventHistory(
            events: page.events,
            nextCursor: page.nextCursor.map(RuntimeEventCursorWireCodec.encode),
            matchingCount: page.matchingCount,
            readError: page.readError
        )
    }

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        loadVitalDBObservationSnapshot().observation
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        let repository = SQLiteVitalDBObservationRepository(
            url: URL(fileURLWithPath: paths.runtimeObservabilityDB)
        )
        do {
            return RuntimeVitalDBObservationSnapshot.fromOptional(try repository.loadLatestObservation())
        } catch {
            return .failed(readError: String(describing: error))
        }
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        let repository = SQLiteVitalDBObservationRepository(
            url: URL(fileURLWithPath: paths.runtimeObservabilityDB)
        )
        var readErrors: [String] = []
        var observations: [VitalDBObservationDocument]
        do {
            observations = try repository.loadObservations()
        } catch {
            observations = []
            readErrors.append("observations=\(String(describing: error))")
        }
        if let statusObservation = statusObservation(),
           !observations.contains(where: { $0.observedAt == statusObservation.observedAt }) {
            observations.append(statusObservation)
        }
        let activityBuckets: [VitalDBRecorderActivityBucketRecord]
        var activityHistory: RuntimeVitalRecorderActivityHistory?
        do {
            activityBuckets = try repository.loadRecorderActivityBuckets()
            activityHistory = RuntimeVitalRecorderActivityHistory.fromProjection(
                activityBuckets,
                readError: readErrors.isEmpty ? nil : readErrors.joined(separator: ";")
            )
        } catch {
            activityBuckets = []
            readErrors.append("activityBuckets=\(String(describing: error))")
            activityHistory = RuntimeVitalRecorderActivityHistory.unavailable(readError: readErrors.joined(separator: ";"))
        }
        return RuntimeVitalRecorderHistory(
            observations: observations,
            activityBuckets: activityBuckets,
            activityHistory: activityHistory ?? RuntimeVitalRecorderActivityHistory.unavailable(
                readError: readErrors.isEmpty ? nil : readErrors.joined(separator: ";")
            )
        )
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        let repository = SQLiteVitalDBObservationRepository(url: URL(fileURLWithPath: paths.runtimeObservabilityDB))
        var readErrors: [String] = []
        let assignments: [VitalDBBedAssignmentRecord]
        let events: [VitalDBRelationshipEventRecord]
        do {
            assignments = try repository.loadBedAssignments()
        } catch {
            assignments = []
            readErrors.append("assignments=\(String(describing: error))")
        }
        do {
            events = try repository.loadRelationshipEvents()
        } catch {
            events = []
            readErrors.append("events=\(String(describing: error))")
        }
        return RuntimeVitalRelationshipHistory(
            assignments: assignments.map(RuntimeVitalBedAssignmentRecord.init),
            events: events.map(RuntimeVitalRelationshipEventRecord.init),
            readError: readErrors.isEmpty ? nil : readErrors.joined(separator: ";")
        )
    }

    private func statusObservation() -> VitalDBObservationDocument? {
        if let statusObservationProvider {
            return statusObservationProvider()
        }
        switch JSONFileRuntimeStatusRepository(
            url: URL(fileURLWithPath: paths.runtimeStatus)
        ).loadResult() {
        case .loaded(let document):
            return document.vitalDBObservation
        case .missing, .failed:
            return nil
        }
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
            status: RuntimeVitalBedStatus(rawValue: record.status) ?? .unknown,
            patientConnected: record.patientConnected,
            observationCount: record.observationCount
        )
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
