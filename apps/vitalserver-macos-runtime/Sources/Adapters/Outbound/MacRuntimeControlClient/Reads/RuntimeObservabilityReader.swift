import Contracts
import Application
import Domain
import Foundation
import RuntimeControl
import Errors

protocol RuntimeObservabilityReading: Sendable {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
}

extension RuntimeObservabilityReading {
    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        loadVitalDBObservationSnapshot().observation
    }
}

struct SystemRuntimeObservabilityReader: RuntimeObservabilityReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let currentObservationProvider: RuntimeVitalDBCurrentObservationProvider

    init(
        paths: RuntimePaths,
        currentObservationProvider: RuntimeVitalDBCurrentObservationProvider
    ) {
        self.paths = paths
        self.currentObservationProvider = currentObservationProvider
    }

    static func live(paths: RuntimePaths) -> SystemRuntimeObservabilityReader {
        SystemRuntimeObservabilityReader(
            paths: paths,
            currentObservationProvider: .live(paths: paths)
        )
    }

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEvents(query: RuntimeEventQuery(limit: limit))
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        let primary = JSONLRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeEvents))
        let secondary = SQLiteRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeObservabilityDB))
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
        let currentRead = currentObservationProvider.load()
        do {
            let projectedObservation = try repository.loadLatestObservation()
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
        } catch {
            let readError = joinedReadError([
                "projection=\(String(describing: error))",
                currentRead.readError,
            ])
            if let currentObservation = currentRead.observation {
                return RuntimeVitalDBObservationSnapshot(
                    state: .loaded,
                    observation: currentObservation,
                    readError: readError
                )
            }
            return .failed(readError: readError ?? String(describing: error))
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
        let currentRead = currentObservationProvider.load()
        if let readError = currentRead.readError {
            readErrors.append("currentObservation=\(readError)")
        }
        if let currentObservation = currentRead.observation,
           !observations.contains(where: { $0.observedAt == currentObservation.observedAt }) {
            observations.append(currentObservation)
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
        let readError = joinedReadError(readErrors.map(Optional.some))
        return RuntimeVitalRecorderHistory(
            observations: observations,
            activityBuckets: activityBuckets,
            activityHistory: activityHistory ?? RuntimeVitalRecorderActivityHistory.unavailable(readError: readError),
            readError: readError
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

}

enum RuntimeVitalDBCurrentObservationSource: String, Equatable, Sendable {
    case guestRuntimeState
    case runtimeStatus
}

struct RuntimeVitalDBCurrentObservationRead: Equatable, Sendable {
    let source: RuntimeVitalDBCurrentObservationSource?
    let observation: VitalDBObservationDocument?
    let readIssues: [String]

    var readError: String? {
        joinedReadError(readIssues.map(Optional.some))
    }

    static func loaded(
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

    static func unavailable(readIssues: [String] = []) -> RuntimeVitalDBCurrentObservationRead {
        RuntimeVitalDBCurrentObservationRead(
            source: nil,
            observation: nil,
            readIssues: readIssues
        )
    }
}

struct RuntimeVitalDBCurrentObservationProvider: Sendable {
    private let loadCurrentObservation: @Sendable () -> RuntimeVitalDBCurrentObservationRead

    init(load: @escaping @Sendable () -> RuntimeVitalDBCurrentObservationRead) {
        self.loadCurrentObservation = load
    }

    func load() -> RuntimeVitalDBCurrentObservationRead {
        loadCurrentObservation()
    }

    static func live(paths: RuntimePaths) -> RuntimeVitalDBCurrentObservationProvider {
        let runtimeStatePath = paths.runtimeState
        let runtimeStatusPath = paths.runtimeStatus
        return RuntimeVitalDBCurrentObservationProvider {
            let guestStateReader = GuestRuntimeStateVitalDBObservationReader(
                path: runtimeStatePath,
                fileStore: SystemRuntimeFileStore()
            )
            let statusReader = RuntimeStatusVitalDBObservationReader(
                url: URL(fileURLWithPath: runtimeStatusPath)
            )
            var readIssues: [String] = []
            switch guestStateReader.load() {
            case .loaded(let observation):
                if let observation {
                    return .loaded(observation, source: .guestRuntimeState)
                }
            case .missing:
                readIssues.append("runtimeState=missing")
            case .failed(let message):
                readIssues.append("runtimeState=\(message)")
            }

            switch statusReader.load() {
            case .loaded(let observation):
                if let observation {
                    return .loaded(observation, source: .runtimeStatus, readIssues: readIssues)
                }
            case .missing:
                readIssues.append("runtimeStatus=missing")
            case .failed(let message):
                readIssues.append("runtimeStatus=\(message)")
            }
            return .unavailable(readIssues: readIssues)
        }
    }
}

private enum RuntimeVitalDBObservationDocumentRead {
    case missing
    case loaded(VitalDBObservationDocument?)
    case failed(String)
}

private struct GuestRuntimeStateVitalDBObservationReader {
    let path: String
    let fileStore: RuntimeFileReading

    func load() -> RuntimeVitalDBObservationDocumentRead {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
            return .loaded(document.vitalDBObservation)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private struct RuntimeStatusVitalDBObservationReader {
    let url: URL

    func load() -> RuntimeVitalDBObservationDocumentRead {
        switch JSONFileRuntimeStatusRepository(url: url).loadResult() {
        case .loaded(let document):
            return .loaded(document.vitalDBObservation)
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
        }
    }
}

private func joinedReadError(_ parts: [String?]) -> String? {
    let messages = parts.compactMap { part -> String? in
        guard let part, !part.isEmpty else {
            return nil
        }
        return part
    }
    guard !messages.isEmpty else {
        return nil
    }
    return messages.joined(separator: ";")
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
