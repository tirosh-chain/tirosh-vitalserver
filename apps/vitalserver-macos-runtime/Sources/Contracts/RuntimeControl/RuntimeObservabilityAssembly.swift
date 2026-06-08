import Contracts
import Foundation

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
    case notLoaded
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
        case .notLoaded:
            activityBuckets = []
            activityHistory = RuntimeVitalRecorderActivityHistory.notProvided(
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

public enum RuntimeVitalRecorderActivityWindowAssembler {
    public static func makeWindow(
        query: RuntimeVitalRecorderActivityWindowQuery,
        bounds: VitalDBRecorderActivityBucketBounds?,
        records: [VitalDBRecorderActivityBucketRecord],
        readError: String? = nil
    ) -> RuntimeVitalRecorderActivityWindow {
        if let validationError = query.validationError {
            return RuntimeVitalRecorderActivityWindow(
                state: .invalidRequest,
                query: query,
                page: emptyPage(query: query),
                buckets: [],
                latestSampleAt: nil,
                readError: validationError
            )
        }
        if let readError {
            return RuntimeVitalRecorderActivityWindow(
                state: .readFailed,
                query: query,
                page: emptyPage(query: query),
                buckets: [],
                latestSampleAt: nil,
                readError: readError
            )
        }
        guard let bounds else {
            return RuntimeVitalRecorderActivityWindow(
                state: .empty,
                query: query,
                page: emptyPage(query: query),
                buckets: [],
                latestSampleAt: nil
            )
        }
        guard let firstDate = activityDate(from: bounds.firstBucketStartedAt),
              let latestDate = activityDate(from: bounds.latestBucketStartedAt) else {
            return RuntimeVitalRecorderActivityWindow(
                state: .readFailed,
                query: query,
                page: emptyPage(query: query),
                buckets: [],
                latestSampleAt: nil,
                readError: "activity bucket bounds contain invalid timestamps"
            )
        }

        let firstTimestamp = normalizedTimestamp(firstDate, bucketSeconds: query.bucketSeconds)
        let latestTimestamp = normalizedTimestamp(latestDate, bucketSeconds: query.bucketSeconds)
        let page = pageMetadata(query: query, firstTimestamp: firstTimestamp, latestTimestamp: latestTimestamp)
        let buckets = filledWindowBuckets(
            records: records,
            start: page.windowStartedAt,
            end: page.windowEndedAt,
            bucketSeconds: query.bucketSeconds
        )
        return RuntimeVitalRecorderActivityWindow(
            state: buckets.contains(where: { $0.messageCount > 0 }) ? .loaded : .empty,
            query: query,
            page: page,
            buckets: buckets,
            latestSampleAt: records.map(\.lastObservedAt).max() ?? bounds.latestBucketStartedAt
        )
    }

    public static func windowReadQuery(
        query: RuntimeVitalRecorderActivityWindowQuery,
        bounds: VitalDBRecorderActivityBucketBounds
    ) -> VitalDBRecorderActivityBucketQuery? {
        guard query.validationError == nil,
              let firstDate = activityDate(from: bounds.firstBucketStartedAt),
              let latestDate = activityDate(from: bounds.latestBucketStartedAt) else {
            return nil
        }
        let firstTimestamp = normalizedTimestamp(firstDate, bucketSeconds: query.bucketSeconds)
        let latestTimestamp = normalizedTimestamp(latestDate, bucketSeconds: query.bucketSeconds)
        let page = pageMetadata(query: query, firstTimestamp: firstTimestamp, latestTimestamp: latestTimestamp)
        return VitalDBRecorderActivityBucketQuery(
            vrcode: query.vrcode,
            since: page.windowStartedAt,
            until: page.windowEndedAt,
            limit: 2_000
        )
    }

    private static func emptyPage(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindowPage {
        RuntimeVitalRecorderActivityWindowPage(
            index: 0,
            count: 1,
            windowSeconds: query.period.intervalSeconds ?? RuntimeVitalRecorderActivityWindowQuery.allWindowSeconds,
            windowStartedAt: nil,
            windowEndedAt: nil,
            firstBucketStartedAt: nil,
            latestBucketStartedAt: nil
        )
    }

    private static func pageMetadata(
        query: RuntimeVitalRecorderActivityWindowQuery,
        firstTimestamp: TimeInterval,
        latestTimestamp: TimeInterval
    ) -> RuntimeVitalRecorderActivityWindowPage {
        let windowSeconds = query.period.intervalSeconds ?? RuntimeVitalRecorderActivityWindowQuery.allWindowSeconds
        let bucketsPerWindow = max(windowSeconds / query.bucketSeconds, 1)
        let bucketCount = Int(max(0, (latestTimestamp - firstTimestamp) / Double(query.bucketSeconds))) + 1
        let pageCount: Int
        let pageIndex: Int
        let startTimestamp: TimeInterval
        let endTimestamp: TimeInterval

        if query.period == .all {
            pageCount = max(Int(ceil(Double(bucketCount) / Double(bucketsPerWindow))), 1)
            let latestPageIndex = pageCount - 1
            pageIndex = min(max(query.pageIndex ?? latestPageIndex, 0), latestPageIndex)
            startTimestamp = firstTimestamp + Double(pageIndex * bucketsPerWindow * query.bucketSeconds)
            endTimestamp = min(
                startTimestamp + Double((bucketsPerWindow - 1) * query.bucketSeconds),
                latestTimestamp
            )
        } else {
            pageCount = 1
            pageIndex = 0
            endTimestamp = latestTimestamp
            startTimestamp = max(
                firstTimestamp,
                latestTimestamp - Double((bucketsPerWindow - 1) * query.bucketSeconds)
            )
        }

        return RuntimeVitalRecorderActivityWindowPage(
            index: pageIndex,
            count: pageCount,
            windowSeconds: windowSeconds,
            windowStartedAt: activityString(from: Date(timeIntervalSince1970: startTimestamp)),
            windowEndedAt: activityString(
                from: Date(timeIntervalSince1970: endTimestamp + Double(query.bucketSeconds))
            ),
            firstBucketStartedAt: activityString(from: Date(timeIntervalSince1970: firstTimestamp)),
            latestBucketStartedAt: activityString(from: Date(timeIntervalSince1970: latestTimestamp))
        )
    }

    private static func filledWindowBuckets(
        records: [VitalDBRecorderActivityBucketRecord],
        start: String?,
        end: String?,
        bucketSeconds: Int
    ) -> [VitalDBRecorderActivityBucket] {
        guard let start,
              let end,
              let startDate = activityDate(from: start),
              let endDate = activityDate(from: end) else {
            return []
        }
        let bucketInterval = Double(bucketSeconds)
        let startTimestamp = normalizedTimestamp(startDate, bucketSeconds: bucketSeconds)
        let endTimestamp = normalizedTimestamp(endDate, bucketSeconds: bucketSeconds)
        var existing: [String: VitalDBRecorderActivityBucketAccumulator] = [:]
        for record in records {
            guard let date = activityDate(from: record.bucketStartedAt) else {
                continue
            }
            let key = activityString(
                from: Date(timeIntervalSince1970: normalizedTimestamp(date, bucketSeconds: bucketSeconds))
            )
            var accumulator = existing[key] ?? VitalDBRecorderActivityBucketAccumulator(
                bucketStartedAt: key,
                bucketSeconds: bucketSeconds
            )
            accumulator.add(record)
            existing[key] = accumulator
        }

        var result: [VitalDBRecorderActivityBucket] = []
        var cursor = startTimestamp
        while cursor < endTimestamp {
            let key = activityString(from: Date(timeIntervalSince1970: cursor))
            result.append(existing[key]?.bucket ?? VitalDBRecorderActivityBucket(
                bucketStartedAt: key,
                bucketSeconds: bucketSeconds,
                messageCount: 0,
                byteCount: 0,
                roomCount: 0
            ))
            cursor += bucketInterval
        }
        return result
    }

    private static func normalizedTimestamp(_ date: Date, bucketSeconds: Int) -> TimeInterval {
        let interval = Double(bucketSeconds)
        return floor(date.timeIntervalSince1970 / interval) * interval
    }

    private static func activityDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func activityString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

private struct VitalDBRecorderActivityBucketAccumulator {
    let bucketStartedAt: String
    let bucketSeconds: Int
    var messageCount = 0
    var byteCount = 0
    var roomCount = 0

    mutating func add(_ record: VitalDBRecorderActivityBucketRecord) {
        messageCount += record.messageCount
        byteCount += record.byteCount
        roomCount += record.roomCount
    }

    var bucket: VitalDBRecorderActivityBucket {
        VitalDBRecorderActivityBucket(
            bucketStartedAt: bucketStartedAt,
            bucketSeconds: bucketSeconds,
            messageCount: messageCount,
            byteCount: byteCount,
            roomCount: roomCount
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
