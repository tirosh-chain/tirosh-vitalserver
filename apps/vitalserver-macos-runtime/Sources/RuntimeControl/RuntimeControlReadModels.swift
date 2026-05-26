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
    case proxyOutput
    case proxyError
    case updateActivation
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
    public let appBundlePath: String
    public let packageIdentifier: String
    public let runtimeHomePath: String
    public let backupsPath: String
    public let redisBackupsPath: String

    public init(
        appBundlePath: String = "",
        packageIdentifier: String = "",
        runtimeHomePath: String = "",
        backupsPath: String = "",
        redisBackupsPath: String? = nil
    ) {
        self.appBundlePath = appBundlePath
        self.packageIdentifier = packageIdentifier
        self.runtimeHomePath = runtimeHomePath
        self.backupsPath = backupsPath
        self.redisBackupsPath = redisBackupsPath ?? ""
    }
}

public struct RuntimeEventHistory: Codable, Equatable, Sendable {
    public let events: [RuntimeEventDocument]
    public let nextCursor: String?

    public init(events: [RuntimeEventDocument], nextCursor: String? = nil) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

public enum RuntimeVitalRecorderSummarySource: String, Codable, Equatable, Sendable {
    case vitalDBObservation
    case auditProxy
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
        latestAnomalySeverity: VitalDBAnomalySeverity?
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
    }
}

public struct RuntimeVitalRecorderHistory: Codable, Equatable, Sendable {
    public let updatedAt: String?
    public let recorders: [RuntimeVitalRecorderRecord]

    public init(updatedAt: String? = nil, recorders: [RuntimeVitalRecorderRecord] = []) {
        self.updatedAt = updatedAt
        self.recorders = recorders
    }

    public init(observations: [VitalDBObservationDocument]) {
        let ordered = observations.sorted { $0.observedAt < $1.observedAt }
        guard let latestObservation = ordered.last else {
            self.init()
            return
        }

        var builders: [String: RecorderBuilder] = [:]
        for observation in ordered {
            let bedsByRecorder = Dictionary(
                observation.beds.compactMap { bed in bed.vrcode.map { ($0, bed) } },
                uniquingKeysWith: { _, latest in latest }
            )
            for recorder in observation.recorders {
                var builder = builders[recorder.vrcode] ?? RecorderBuilder(vrcode: recorder.vrcode)
                builder.observe(recorder: recorder, bed: bedsByRecorder[recorder.vrcode], observedAt: observation.observedAt)
                builders[recorder.vrcode] = builder
            }
        }

        let latestRecorders = Dictionary(
            latestObservation.recorders.map { ($0.vrcode, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestBedsByRecorder = Dictionary(
            latestObservation.beds.compactMap { bed in bed.vrcode.map { ($0, bed) } },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestAnomaliesBySubject = Dictionary(grouping: latestObservation.anomalies, by: \.subject)

        let unsortedRecords: [RuntimeVitalRecorderRecord] = builders.values.map { builder in
            let latestRecorder = latestRecorders[builder.vrcode]
            let latestBed = latestBedsByRecorder[builder.vrcode]
            let anomalies = latestAnomaliesBySubject[builder.vrcode] ?? []
            return builder.record(
                latestRecorder: latestRecorder,
                latestBed: latestBed,
                currentAnomalies: anomalies
            )
        }

        let records = unsortedRecords.sorted { lhs, rhs in
            let lhsLastSeen = lhs.lastSeenAt ?? ""
            let rhsLastSeen = rhs.lastSeenAt ?? ""
            if lhsLastSeen == rhsLastSeen {
                return lhs.vrcode < rhs.vrcode
            }
            return lhsLastSeen > rhsLastSeen
        }

        self.init(updatedAt: latestObservation.observedAt, recorders: records)
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
        let connectionRecorders = status.containerObservation?.auditProxyStatus?.recorders ?? []
        let activeConnections = status.containerObservation?.auditProxyStatus?.activeRecorderConnections ?? 0

        if let observation {
            let latest = observation.recorders
                .sorted { ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "") }
                .first
            self.init(
                source: .vitalDBObservation,
                activeConnections: activeConnections,
                knownRecorders: observation.recorders.count,
                onlineRecorders: observation.recorders.filter(\.online).count,
                staleRecorders: observation.recorders.filter(\.stale).count,
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

        let latest = connectionRecorders
            .sorted { ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "") }
            .first
        self.init(
            source: connectionRecorders.isEmpty ? .unavailable : .auditProxy,
            activeConnections: activeConnections,
            knownRecorders: connectionRecorders.count,
            onlineRecorders: 0,
            staleRecorders: 0,
            knownBeds: 0,
            recorderAnomalies: 0,
            observedAt: nil,
            latestRecorder: latest.map {
                RuntimeVitalRecorderReference(
                    vrcode: $0.vrcode,
                    ip: $0.selectedIp,
                    lastSeenAt: $0.lastSeenAt,
                    source: .auditProxy
                )
            }
        )
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

    mutating func observe(recorder: VitalDBRecorderObservation, bed: VitalDBBedObservation?, observedAt: String) {
        observationCount += 1
        let seenAt = recorder.lastSeenAt ?? observedAt
        firstSeenAt = minTimestamp(firstSeenAt, seenAt)
        lastSeenAt = maxTimestamp(lastSeenAt, seenAt)
        lastIP = recorder.ip ?? lastIP
        version = recorder.version ?? version
        bedID = bed?.bedID ?? bedID
        bedName = bed?.name ?? bedName
        patientConnected = bed?.patientConnected ?? patientConnected
    }

    func record(
        latestRecorder: VitalDBRecorderObservation?,
        latestBed: VitalDBBedObservation?,
        currentAnomalies: [VitalDBAnomalyObservation]
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
            latestAnomalySeverity: currentAnomalies.sorted { $0.observedAt > $1.observedAt }.first?.severity
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
