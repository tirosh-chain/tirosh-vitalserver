import Contracts
import Core
import Foundation

public struct RuntimeBackup: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let sizeBytes: UInt64?

    public init(path: String, sizeBytes: UInt64?) {
        self.path = path
        self.sizeBytes = sizeBytes
    }

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public enum RuntimeLogSource: String, Codable, Hashable, Sendable {
    case helperMessage
    case install
    case command
    case launcher
    case vmLaunchOutput
    case vmLaunchError
    case proxyOutput
    case proxyError
    case watchdog
    case updateActivation
    case updateShutdown
    case containers
}

public struct RuntimeLogSourceOption: Codable, Identifiable, Sendable {
    public let id: RuntimeLogSource
    public let title: String

    public init(id: RuntimeLogSource, title: String) {
        self.id = id
        self.title = title
    }
}

public struct VitalFilesFolder: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct RuntimeCommandResult: Codable, Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct RuntimeLogExportResult: Codable, Equatable, Sendable {
    public let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }
}

public struct RuntimeReleaseInfo: Codable, Equatable, Sendable {
    public let helperVersion: String
    public let minimumUpdaterVersion: String
    public let vitalServerVersion: String
    public let services: [RuntimeBundledServiceInfo]

    public init(
        helperVersion: String,
        minimumUpdaterVersion: String,
        vitalServerVersion: String,
        services: [RuntimeBundledServiceInfo]
    ) {
        self.helperVersion = helperVersion
        self.minimumUpdaterVersion = minimumUpdaterVersion
        self.vitalServerVersion = vitalServerVersion
        self.services = services
    }
}

public struct RuntimeBundledServiceInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let image: String
    public let version: String

    public init(name: String, image: String, version: String) {
        self.name = name
        self.image = image
        self.version = version
    }
}

public struct RuntimeInstallInfo: Codable, Equatable, Sendable {
    public let appBundlePath: String?
    public let packageIdentifier: String?
    public let runtimeHomePath: String?
    public let backupsPath: String?
    public let redisBackupsPath: String?

    public init(
        appBundlePath: String? = nil,
        packageIdentifier: String? = nil,
        runtimeHomePath: String? = nil,
        backupsPath: String? = nil,
        redisBackupsPath: String? = nil
    ) {
        self.appBundlePath = appBundlePath
        self.packageIdentifier = packageIdentifier
        self.runtimeHomePath = runtimeHomePath
        self.backupsPath = backupsPath
        self.redisBackupsPath = redisBackupsPath
    }
}

public struct RuntimeEventHistory: Codable, Equatable, Sendable {
    public let events: [RuntimeEventDocument]
    public let nextCursor: String?
    public let matchingCount: Int?

    public init(
        events: [RuntimeEventDocument],
        nextCursor: String? = nil,
        matchingCount: Int? = nil
    ) {
        self.events = events
        self.nextCursor = nextCursor
        self.matchingCount = matchingCount
    }
}

public enum RuntimeVitalRecorderSummarySource: String, Codable, Equatable, Sendable {
    case vitalDBObservation
    case unavailable
}

public struct RuntimeVitalRecorderReference: Codable, Equatable, Sendable {
    public let vrcode: String
    public let ip: String?
    public let lastSeenAt: String?
    public let source: RuntimeVitalRecorderSummarySource

    public init(
        vrcode: String,
        ip: String?,
        lastSeenAt: String?,
        source: RuntimeVitalRecorderSummarySource
    ) {
        self.vrcode = vrcode
        self.ip = ip
        self.lastSeenAt = lastSeenAt
        self.source = source
    }
}

public enum RuntimeVitalRecorderStatus: String, Codable, Equatable, Sendable {
    case online
    case stale
    case offline
    case unknown
}

public enum RuntimeVitalBedStatus: String, Codable, Equatable, Sendable {
    case online
    case stale
    case offline
    case unknown
}

public struct RuntimeVitalRecorderActivityPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String { observedAt }
    public let observedAt: String
    public let windowSeconds: Int
    public let messageCount: Int
    public let byteCount: Int
    public let roomCount: Int
    public let messagesPerSecond: Double
    public let bytesPerSecond: Double
    public let buckets: [VitalDBRecorderActivityBucket]

    public init(
        observedAt: String,
        windowSeconds: Int,
        messageCount: Int,
        byteCount: Int,
        roomCount: Int,
        messagesPerSecond: Double,
        bytesPerSecond: Double,
        buckets: [VitalDBRecorderActivityBucket] = []
    ) {
        self.observedAt = observedAt
        self.windowSeconds = windowSeconds
        self.messageCount = messageCount
        self.byteCount = byteCount
        self.roomCount = roomCount
        self.messagesPerSecond = messagesPerSecond
        self.bytesPerSecond = bytesPerSecond
        self.buckets = buckets
    }

    private enum CodingKeys: String, CodingKey {
        case observedAt
        case windowSeconds
        case messageCount
        case byteCount
        case roomCount
        case messagesPerSecond
        case bytesPerSecond
        case buckets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observedAt = try container.decode(String.self, forKey: .observedAt)
        windowSeconds = try container.decode(Int.self, forKey: .windowSeconds)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        roomCount = try container.decodeIfPresent(Int.self, forKey: .roomCount) ?? 0
        messagesPerSecond = try container.decodeIfPresent(Double.self, forKey: .messagesPerSecond) ?? 0
        bytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .bytesPerSecond) ?? 0
        buckets = try container.decodeIfPresent([VitalDBRecorderActivityBucket].self, forKey: .buckets) ?? []
    }
}

public struct RuntimeVitalRecorderRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { vrcode }
    public let vrcode: String
    public let status: RuntimeVitalRecorderStatus
    public let lastIP: String?
    public let version: String?
    public let bedID: String?
    public let bedName: String?
    public let patientConnected: Bool?
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let observationCount: Int
    public let currentAnomalyCount: Int
    public let latestAnomalySeverity: VitalDBAnomalySeverity?
    public let presentInLatestObservation: Bool
    public let activityTimeline: [RuntimeVitalRecorderActivityPoint]

    public init(
        vrcode: String,
        status: RuntimeVitalRecorderStatus,
        lastIP: String?,
        version: String?,
        bedID: String?,
        bedName: String?,
        patientConnected: Bool?,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observationCount: Int,
        currentAnomalyCount: Int,
        latestAnomalySeverity: VitalDBAnomalySeverity?,
        presentInLatestObservation: Bool = true
    ) {
        self.init(
            vrcode: vrcode,
            status: status,
            lastIP: lastIP,
            version: version,
            bedID: bedID,
            bedName: bedName,
            patientConnected: patientConnected,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt,
            observationCount: observationCount,
            currentAnomalyCount: currentAnomalyCount,
            latestAnomalySeverity: latestAnomalySeverity,
            presentInLatestObservation: presentInLatestObservation,
            activityTimeline: []
        )
    }

    public init(
        vrcode: String,
        status: RuntimeVitalRecorderStatus,
        lastIP: String?,
        version: String?,
        bedID: String?,
        bedName: String?,
        patientConnected: Bool?,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observationCount: Int,
        currentAnomalyCount: Int,
        latestAnomalySeverity: VitalDBAnomalySeverity?,
        presentInLatestObservation: Bool,
        activityTimeline: [RuntimeVitalRecorderActivityPoint]
    ) {
        self.vrcode = vrcode
        self.status = status
        self.lastIP = lastIP
        self.version = version
        self.bedID = bedID
        self.bedName = bedName
        self.patientConnected = patientConnected
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.observationCount = observationCount
        self.currentAnomalyCount = currentAnomalyCount
        self.latestAnomalySeverity = latestAnomalySeverity
        self.presentInLatestObservation = presentInLatestObservation
        self.activityTimeline = activityTimeline
    }
}

public struct RuntimeVitalBedRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bedID }
    public let bedID: String
    public let name: String?
    public let vrcode: String?
    public let status: RuntimeVitalBedStatus
    public let patientConnected: Bool?
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let observationCount: Int
    public let currentAnomalyCount: Int
    public let latestAnomalySeverity: VitalDBAnomalySeverity?

    public init(
        bedID: String,
        name: String?,
        vrcode: String?,
        status: RuntimeVitalBedStatus,
        patientConnected: Bool?,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observationCount: Int,
        currentAnomalyCount: Int,
        latestAnomalySeverity: VitalDBAnomalySeverity?
    ) {
        self.bedID = bedID
        self.name = name
        self.vrcode = vrcode
        self.status = status
        self.patientConnected = patientConnected
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.observationCount = observationCount
        self.currentAnomalyCount = currentAnomalyCount
        self.latestAnomalySeverity = latestAnomalySeverity
    }
}

public struct RuntimeVitalRecorderHistory: Codable, Equatable, Sendable {
    public let updatedAt: String?
    public let recorders: [RuntimeVitalRecorderRecord]
    public let beds: [RuntimeVitalBedRecord]
    public let activityHistory: RuntimeVitalRecorderActivityHistory

    public init(
        updatedAt: String? = nil,
        recorders: [RuntimeVitalRecorderRecord] = [],
        beds: [RuntimeVitalBedRecord] = [],
        activityHistory: RuntimeVitalRecorderActivityHistory = .unavailable()
    ) {
        self.updatedAt = updatedAt
        self.recorders = recorders
        self.beds = beds
        self.activityHistory = activityHistory
    }

    public init(observations: [VitalDBObservationDocument]) {
        self.init(observations: observations, projectedActivityBuckets: nil)
    }

    public init(
        observations: [VitalDBObservationDocument],
        activityBuckets: [VitalDBRecorderActivityBucketRecord],
        activityHistory: RuntimeVitalRecorderActivityHistory? = nil
    ) {
        self.init(
            observations: observations,
            projectedActivityBuckets: activityBuckets,
            activityHistory: activityHistory
        )
    }

    private init(
        observations: [VitalDBObservationDocument],
        projectedActivityBuckets activityBuckets: [VitalDBRecorderActivityBucketRecord]?,
        activityHistory: RuntimeVitalRecorderActivityHistory? = nil
    ) {
        let ordered = observations.sorted { $0.observedAt < $1.observedAt }
        guard let latestObservation = ordered.last else {
            self.init(activityHistory: activityHistory ?? .unavailable())
            return
        }

        var builders: [String: RecorderBuilder] = [:]
        var bedBuilders: [String: BedBuilder] = [:]
        for observation in ordered {
            let bedsByRecorder = Dictionary(
                observation.beds.compactMap { bed in bed.vrcode.map { ($0, bed) } },
                uniquingKeysWith: { _, latest in latest }
            )
            for recorder in uniqueRecordersByVrcode(observation.recorders) {
                var builder = builders[recorder.vrcode] ?? RecorderBuilder(vrcode: recorder.vrcode)
                builder.observe(
                    recorder: recorder,
                    bed: bedsByRecorder[recorder.vrcode],
                    observedAt: observation.observedAt,
                    includeSnapshotActivity: activityBuckets == nil
                )
                builders[recorder.vrcode] = builder
            }
            for bed in uniqueBedsByID(observation.beds) {
                var builder = bedBuilders[bed.bedID] ?? BedBuilder(bedID: bed.bedID)
                builder.observe(bed: bed, observedAt: observation.observedAt)
                bedBuilders[bed.bedID] = builder
            }
        }

        let latestRecorders = Dictionary(
            uniqueRecordersByVrcode(latestObservation.recorders).map { ($0.vrcode, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestBedsByRecorder = Dictionary(
            latestObservation.beds.compactMap { bed in bed.vrcode.map { ($0, bed) } },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestBeds = Dictionary(
            uniqueBedsByID(latestObservation.beds).map { ($0.bedID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestAnomaliesBySubject = Dictionary(grouping: latestObservation.anomalies, by: \.subject)
        let projectedActivityByVrcode = activityBuckets.map(projectedActivityTimelineByVrcode)

        let unsortedRecords: [RuntimeVitalRecorderRecord] = builders.values.map { builder in
            let latestRecorder = latestRecorders[builder.vrcode]
            let latestBed = latestBedsByRecorder[builder.vrcode]
            let anomalies = latestAnomaliesBySubject[builder.vrcode] ?? []
            return builder.record(
                latestRecorder: latestRecorder,
                latestBed: latestBed,
                currentAnomalies: anomalies,
                activityTimeline: projectedActivityByVrcode?[builder.vrcode]
            )
        }

        let records = unsortedRecords.sorted { lhs, rhs in
            switch compareReportedTimestamp(lhs.lastSeenAt, rhs.lastSeenAt) {
            case .orderedDescending:
                return true
            case .orderedAscending:
                return false
            case .orderedSame:
                return lhs.vrcode < rhs.vrcode
            }
        }

        let beds = bedBuilders.values.map { builder in
            let latestBed = latestBeds[builder.bedID]
            let anomalies = latestAnomaliesBySubject[builder.bedID] ?? []
            return builder.record(latestBed: latestBed, currentAnomalies: anomalies)
        }
        .sorted { lhs, rhs in
            switch compareReportedTimestamp(lhs.lastSeenAt, rhs.lastSeenAt) {
            case .orderedDescending:
                return true
            case .orderedAscending:
                return false
            case .orderedSame:
                return lhs.bedID < rhs.bedID
            }
        }

        self.init(
            updatedAt: latestObservation.observedAt,
            recorders: records,
            beds: beds,
            activityHistory: activityHistory ?? .fromProjection(activityBuckets ?? [])
        )
    }
}

public struct RuntimeVitalRecorderActivityHistory: Codable, Equatable, Sendable {
    public let source: RuntimeVitalRecorderActivityHistorySource
    public let bucketCount: Int
    public let earliestBucketStartedAt: String?
    public let latestBucketStartedAt: String?
    public let readError: String?

    public init(
        source: RuntimeVitalRecorderActivityHistorySource,
        bucketCount: Int,
        earliestBucketStartedAt: String? = nil,
        latestBucketStartedAt: String? = nil,
        readError: String? = nil
    ) {
        self.source = source
        self.bucketCount = bucketCount
        self.earliestBucketStartedAt = earliestBucketStartedAt
        self.latestBucketStartedAt = latestBucketStartedAt
        self.readError = readError
    }

    public static func fromProjection(
        _ buckets: [VitalDBRecorderActivityBucketRecord],
        readError: String? = nil
    ) -> RuntimeVitalRecorderActivityHistory {
        RuntimeVitalRecorderActivityHistory(
            source: .sqliteProjection,
            bucketCount: buckets.count,
            earliestBucketStartedAt: buckets.map(\.bucketStartedAt).min(),
            latestBucketStartedAt: buckets.map(\.bucketStartedAt).max(),
            readError: readError
        )
    }

    public static func unavailable(readError: String? = nil) -> RuntimeVitalRecorderActivityHistory {
        RuntimeVitalRecorderActivityHistory(
            source: .unavailable,
            bucketCount: 0,
            readError: readError
        )
    }
}

public enum RuntimeVitalRecorderActivityHistorySource: String, Codable, Equatable, Sendable {
    case sqliteProjection
    case unavailable
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

public struct RuntimeVitalRelationshipHistory: Codable, Equatable, Sendable {
    public let assignments: [RuntimeVitalBedAssignmentRecord]
    public let events: [RuntimeVitalRelationshipEventRecord]

    public init(
        assignments: [RuntimeVitalBedAssignmentRecord] = [],
        events: [RuntimeVitalRelationshipEventRecord] = []
    ) {
        self.assignments = assignments
        self.events = events
    }
}

public struct RuntimeVitalRecorderSummary: Codable, Equatable, Sendable {
    public let source: RuntimeVitalRecorderSummarySource
    public let activeConnections: Int
    public let knownRecorders: Int
    public let onlineRecorders: Int
    public let staleRecorders: Int
    public let knownBeds: Int
    public let recorderAnomalies: Int
    public let observedAt: String?
    public let latestRecorder: RuntimeVitalRecorderReference?

    public init(
        source: RuntimeVitalRecorderSummarySource,
        activeConnections: Int,
        knownRecorders: Int,
        onlineRecorders: Int,
        staleRecorders: Int,
        knownBeds: Int,
        recorderAnomalies: Int,
        observedAt: String?,
        latestRecorder: RuntimeVitalRecorderReference?
    ) {
        self.source = source
        self.activeConnections = activeConnections
        self.knownRecorders = knownRecorders
        self.onlineRecorders = onlineRecorders
        self.staleRecorders = staleRecorders
        self.knownBeds = knownBeds
        self.recorderAnomalies = recorderAnomalies
        self.observedAt = observedAt
        self.latestRecorder = latestRecorder
    }

    public init(status: RuntimeStatus, vitalDBObservation: VitalDBObservationDocument? = nil) {
        let observation = vitalDBObservation ?? status.vitalDBObservation
        let activeConnections = status.containerObservation?.auditProxyStatus?.activeRecorderConnections ?? 0

        if let observation {
            let recorders = uniqueRecordersByVrcode(observation.recorders)
            let latest = recorders
                .sorted { compareReportedTimestamp($0.lastSeenAt, $1.lastSeenAt) == .orderedDescending }
                .first
            self.init(
                source: .vitalDBObservation,
                activeConnections: activeConnections,
                knownRecorders: recorders.count,
                onlineRecorders: recorders.filter(\.online).count,
                staleRecorders: recorders.filter(\.stale).count,
                knownBeds: observation.beds.count,
                recorderAnomalies: observation.anomalies.count,
                observedAt: observation.observedAt,
                latestRecorder: latest.map {
                    RuntimeVitalRecorderReference(
                        vrcode: $0.vrcode,
                        ip: $0.ip,
                        lastSeenAt: $0.lastSeenAt,
                        source: .vitalDBObservation
                    )
                }
            )
            return
        }

        self.init(
            source: .unavailable,
            activeConnections: activeConnections,
            knownRecorders: 0,
            onlineRecorders: 0,
            staleRecorders: 0,
            knownBeds: 0,
            recorderAnomalies: 0,
            observedAt: nil,
            latestRecorder: nil
        )
    }
}

private func uniqueRecordersByVrcode(_ recorders: [VitalDBRecorderObservation]) -> [VitalDBRecorderObservation] {
    Dictionary(
        recorders.map { ($0.vrcode, $0) },
        uniquingKeysWith: preferredRecorder
    )
    .values
    .sorted { $0.vrcode < $1.vrcode }
}

private func uniqueBedsByID(_ beds: [VitalDBBedObservation]) -> [VitalDBBedObservation] {
    Dictionary(
        beds.map { ($0.bedID, $0) },
        uniquingKeysWith: preferredBed
    )
    .values
    .sorted { $0.bedID < $1.bedID }
}

private func preferredRecorder(
    _ current: VitalDBRecorderObservation,
    _ candidate: VitalDBRecorderObservation
) -> VitalDBRecorderObservation {
    let timestampOrder = compareReportedTimestamp(candidate.lastSeenAt, current.lastSeenAt)
    if timestampOrder != .orderedSame {
        return timestampOrder == .orderedDescending ? candidate : current
    }
    if candidate.online != current.online {
        return candidate.online ? candidate : current
    }
    if candidate.stale != current.stale {
        return candidate.stale ? current : candidate
    }
    return candidate
}

private func preferredBed(
    _ current: VitalDBBedObservation,
    _ candidate: VitalDBBedObservation
) -> VitalDBBedObservation {
    let timestampOrder = compareReportedTimestamp(candidate.lastSeenAt, current.lastSeenAt)
    if timestampOrder != .orderedSame {
        return timestampOrder == .orderedDescending ? candidate : current
    }
    if candidate.online != current.online {
        return candidate.online ? candidate : current
    }
    return candidate
}

private func compareReportedTimestamp(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
    switch (lhs, rhs) {
    case let (lhs?, rhs?) where lhs != rhs:
        return lhs > rhs ? .orderedDescending : .orderedAscending
    case (.some, .some):
        return .orderedSame
    case (.some, nil):
        return .orderedDescending
    case (nil, .some):
        return .orderedAscending
    case (nil, nil):
        return .orderedSame
    }
}

private func projectedActivityTimelineByVrcode(
    _ records: [VitalDBRecorderActivityBucketRecord]
) -> [String: [RuntimeVitalRecorderActivityPoint]] {
    let grouped = Dictionary(grouping: records, by: \.vrcode)
    return grouped.mapValues { records in
        records
            .sorted { $0.bucketStartedAt < $1.bucketStartedAt }
            .map { record in
                RuntimeVitalRecorderActivityPoint(
                    observedAt: record.lastObservedAt,
                    windowSeconds: record.bucketSeconds,
                    messageCount: record.messageCount,
                    byteCount: record.byteCount,
                    roomCount: record.roomCount,
                    messagesPerSecond: Double(record.messageCount) / Double(max(record.bucketSeconds, 1)),
                    bytesPerSecond: Double(record.byteCount) / Double(max(record.bucketSeconds, 1)),
                    buckets: [record.bucket]
                )
            }
    }
}

private struct RecorderBuilder {
    let vrcode: String
    var lastIP: String?
    var version: String?
    var bedID: String?
    var bedName: String?
    var patientConnected: Bool?
    var firstSeenAt: String?
    var lastSeenAt: String?
    var observationCount = 0
    var activityTimeline: [RuntimeVitalRecorderActivityPoint] = []

    mutating func observe(
        recorder: VitalDBRecorderObservation,
        bed: VitalDBBedObservation?,
        observedAt: String,
        includeSnapshotActivity: Bool = true
    ) {
        observationCount += 1
        let seenAt = recorder.lastSeenAt ?? observedAt
        firstSeenAt = minTimestamp(firstSeenAt, seenAt)
        lastSeenAt = maxTimestamp(lastSeenAt, seenAt)
        lastIP = recorder.ip ?? lastIP
        version = recorder.version ?? version
        bedID = bed?.bedID ?? bedID
        bedName = bed?.name ?? bedName
        patientConnected = bed?.patientConnected ?? patientConnected
        if includeSnapshotActivity, let activity = recorder.activity {
            activityTimeline.append(
                RuntimeVitalRecorderActivityPoint(
                    observedAt: observedAt,
                    windowSeconds: activity.windowSeconds,
                    messageCount: activity.messageCount,
                    byteCount: activity.byteCount,
                    roomCount: activity.roomCount,
                    messagesPerSecond: activity.messagesPerSecond,
                    bytesPerSecond: activity.bytesPerSecond,
                    buckets: activity.buckets
                )
            )
        }
    }

    func record(
        latestRecorder: VitalDBRecorderObservation?,
        latestBed: VitalDBBedObservation?,
        currentAnomalies: [VitalDBAnomalyObservation],
        activityTimeline projectedActivityTimeline: [RuntimeVitalRecorderActivityPoint]? = nil
    ) -> RuntimeVitalRecorderRecord {
        RuntimeVitalRecorderRecord(
            vrcode: vrcode,
            status: status(latestRecorder),
            lastIP: latestRecorder?.ip ?? lastIP,
            version: latestRecorder?.version ?? version,
            bedID: latestBed?.bedID ?? bedID,
            bedName: latestBed?.name ?? bedName,
            patientConnected: latestBed?.patientConnected ?? patientConnected,
            firstSeenAt: firstSeenAt,
            lastSeenAt: latestRecorder?.lastSeenAt ?? lastSeenAt,
            observationCount: observationCount,
            currentAnomalyCount: currentAnomalies.count,
            latestAnomalySeverity: currentAnomalies.sorted { $0.observedAt > $1.observedAt }.first?.severity,
            presentInLatestObservation: latestRecorder != nil,
            activityTimeline: projectedActivityTimeline ?? activityTimeline.sorted { $0.observedAt < $1.observedAt }
        )
    }

    private func status(_ recorder: VitalDBRecorderObservation?) -> RuntimeVitalRecorderStatus {
        guard let recorder else {
            return .offline
        }
        if recorder.online {
            return .online
        }
        if recorder.stale {
            return .stale
        }
        return .offline
    }

    private func minTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.min(current, next)
    }

    private func maxTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.max(current, next)
    }
}

private struct BedBuilder {
    let bedID: String
    var name: String?
    var vrcode: String?
    var patientConnected: Bool?
    var firstSeenAt: String?
    var lastSeenAt: String?
    var observationCount = 0

    mutating func observe(bed: VitalDBBedObservation, observedAt: String) {
        observationCount += 1
        let seenAt = bed.lastSeenAt ?? observedAt
        firstSeenAt = minTimestamp(firstSeenAt, seenAt)
        lastSeenAt = maxTimestamp(lastSeenAt, seenAt)
        name = bed.name ?? name
        vrcode = bed.vrcode ?? vrcode
        patientConnected = bed.patientConnected ?? patientConnected
    }

    func record(
        latestBed: VitalDBBedObservation?,
        currentAnomalies: [VitalDBAnomalyObservation]
    ) -> RuntimeVitalBedRecord {
        RuntimeVitalBedRecord(
            bedID: bedID,
            name: latestBed?.name ?? name,
            vrcode: latestBed?.vrcode ?? vrcode,
            status: status(latestBed),
            patientConnected: latestBed?.patientConnected ?? patientConnected,
            firstSeenAt: firstSeenAt,
            lastSeenAt: latestBed?.lastSeenAt ?? lastSeenAt,
            observationCount: observationCount,
            currentAnomalyCount: currentAnomalies.count,
            latestAnomalySeverity: currentAnomalies.sorted { $0.observedAt > $1.observedAt }.first?.severity
        )
    }

    private func status(_ bed: VitalDBBedObservation?) -> RuntimeVitalBedStatus {
        guard let bed else {
            return .offline
        }
        return bed.online ? .online : .stale
    }

    private func minTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.min(current, next)
    }

    private func maxTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.max(current, next)
    }
}

public struct RuntimeControlOverview: Codable, Equatable, Sendable {
    public let status: RuntimeStatus
    public let settings: RuntimeSettings
    public let release: RuntimeReleaseInfo
    public let install: RuntimeInstallInfo
    public let vitalDBObservation: VitalDBObservationDocument?
    public let vitalRecorder: RuntimeVitalRecorderSummary

    public init(
        status: RuntimeStatus,
        settings: RuntimeSettings,
        release: RuntimeReleaseInfo,
        install: RuntimeInstallInfo,
        vitalDBObservation: VitalDBObservationDocument? = nil
    ) {
        let observation = vitalDBObservation ?? status.vitalDBObservation
        self.status = status
        self.settings = settings
        self.release = release
        self.install = install
        self.vitalDBObservation = observation
        self.vitalRecorder = RuntimeVitalRecorderSummary(status: status, vitalDBObservation: observation)
    }
}
