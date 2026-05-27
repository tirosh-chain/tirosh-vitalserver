import Foundation

public enum VitalDBAnomalyKind: Codable, Equatable, Sendable {
    case offline
    case duplicateIP
    case backendUnavailable
    case staleRecorder
    case observerUnhealthy
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "offline":
            self = .offline
        case "duplicate-ip":
            self = .duplicateIP
        case "backend-unavailable":
            self = .backendUnavailable
        case "stale-recorder":
            self = .staleRecorder
        case "observer-unhealthy":
            self = .observerUnhealthy
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .offline:
            return "offline"
        case .duplicateIP:
            return "duplicate-ip"
        case .backendUnavailable:
            return "backend-unavailable"
        case .staleRecorder:
            return "stale-recorder"
        case .observerUnhealthy:
            return "observer-unhealthy"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum VitalDBAnomalySeverity: Codable, Equatable, Sendable {
    case info
    case warning
    case critical
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "info":
            self = .info
        case "warning":
            self = .warning
        case "critical":
            self = .critical
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .info:
            return "info"
        case .warning:
            return "warning"
        case .critical:
            return "critical"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VitalDBRecorderObservation: Codable, Equatable, Sendable {
    public let vrcode: String
    public let ip: String?
    public let lastSeenAt: String?
    public let version: String?
    public let info: String?
    public let config: String?
    public let online: Bool
    public let stale: Bool
    public let activity: VitalDBRecorderActivityObservation?

    public init(
        vrcode: String,
        ip: String? = nil,
        lastSeenAt: String? = nil,
        version: String? = nil,
        info: String? = nil,
        config: String? = nil,
        online: Bool,
        stale: Bool = false
    ) {
        self.init(
            vrcode: vrcode,
            ip: ip,
            lastSeenAt: lastSeenAt,
            version: version,
            info: info,
            config: config,
            online: online,
            stale: stale,
            activity: nil
        )
    }

    public init(
        vrcode: String,
        ip: String? = nil,
        lastSeenAt: String? = nil,
        version: String? = nil,
        info: String? = nil,
        config: String? = nil,
        online: Bool,
        stale: Bool = false,
        activity: VitalDBRecorderActivityObservation?
    ) {
        self.vrcode = vrcode
        self.ip = ip
        self.lastSeenAt = lastSeenAt
        self.version = version
        self.info = info
        self.config = config
        self.online = online
        self.stale = stale
        self.activity = activity
    }
}

public struct VitalDBRecorderActivityObservation: Codable, Equatable, Sendable {
    public let windowSeconds: Int
    public let messageCount: Int
    public let byteCount: Int
    public let roomCount: Int
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let messagesPerSecond: Double
    public let bytesPerSecond: Double

    public init(
        windowSeconds: Int,
        messageCount: Int,
        byteCount: Int,
        roomCount: Int = 0,
        firstSeenAt: String? = nil,
        lastSeenAt: String? = nil,
        messagesPerSecond: Double = 0,
        bytesPerSecond: Double = 0
    ) {
        self.windowSeconds = windowSeconds
        self.messageCount = messageCount
        self.byteCount = byteCount
        self.roomCount = roomCount
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.messagesPerSecond = messagesPerSecond
        self.bytesPerSecond = bytesPerSecond
    }
}

public struct VitalDBBedObservation: Codable, Equatable, Sendable {
    public let bedID: String
    public let name: String?
    public let vrcode: String?
    public let lastSeenAt: String?
    public let patientConnected: Bool?
    public let online: Bool

    public init(
        bedID: String,
        name: String? = nil,
        vrcode: String? = nil,
        lastSeenAt: String? = nil,
        patientConnected: Bool? = nil,
        online: Bool
    ) {
        self.bedID = bedID
        self.name = name
        self.vrcode = vrcode
        self.lastSeenAt = lastSeenAt
        self.patientConnected = patientConnected
        self.online = online
    }
}

public struct VitalDBDeviceObservation: Codable, Equatable, Sendable {
    public let bedID: String
    public let rawValue: String

    public init(bedID: String, rawValue: String) {
        self.bedID = bedID
        self.rawValue = rawValue
    }
}

public struct VitalDBFilterObservation: Codable, Equatable, Sendable {
    public let bedID: String
    public let rawValue: String

    public init(bedID: String, rawValue: String) {
        self.bedID = bedID
        self.rawValue = rawValue
    }
}

public struct VitalDBProxyConnectionObservation: Codable, Equatable, Sendable {
    public let observedAt: String
    public let remoteAddress: String?
    public let remotePort: String?
    public let requestURI: String?
    public let status: String?
    public let upstreamStatus: String?
    public let upstreamResponseTime: String?
    public let websocketHandshake: Bool

    public init(
        observedAt: String,
        remoteAddress: String? = nil,
        remotePort: String? = nil,
        requestURI: String? = nil,
        status: String? = nil,
        upstreamStatus: String? = nil,
        upstreamResponseTime: String? = nil,
        websocketHandshake: Bool = false
    ) {
        self.observedAt = observedAt
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.requestURI = requestURI
        self.status = status
        self.upstreamStatus = upstreamStatus
        self.upstreamResponseTime = upstreamResponseTime
        self.websocketHandshake = websocketHandshake
    }
}

public struct VitalDBAnomalyObservation: Codable, Equatable, Sendable {
    public let id: String
    public let kind: VitalDBAnomalyKind
    public let severity: VitalDBAnomalySeverity
    public let observedAt: String
    public let subject: String
    public let message: String

    public init(
        id: String,
        kind: VitalDBAnomalyKind,
        severity: VitalDBAnomalySeverity,
        observedAt: String,
        subject: String,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.observedAt = observedAt
        self.subject = subject
        self.message = message
    }
}

public struct VitalDBObservationDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let observedAt: String
    public let ready: Bool
    public let recorderOnlineThresholdSeconds: Int
    public let recorders: [VitalDBRecorderObservation]
    public let beds: [VitalDBBedObservation]
    public let devices: [VitalDBDeviceObservation]
    public let filters: [VitalDBFilterObservation]
    public let proxyConnections: [VitalDBProxyConnectionObservation]
    public let anomalies: [VitalDBAnomalyObservation]

    public init(
        schemaVersion: Int = 1,
        source: String = "vitaldb-observer",
        observedAt: String,
        ready: Bool,
        recorderOnlineThresholdSeconds: Int,
        recorders: [VitalDBRecorderObservation] = [],
        beds: [VitalDBBedObservation] = [],
        devices: [VitalDBDeviceObservation] = [],
        filters: [VitalDBFilterObservation] = [],
        proxyConnections: [VitalDBProxyConnectionObservation] = [],
        anomalies: [VitalDBAnomalyObservation] = []
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.observedAt = observedAt
        self.ready = ready
        self.recorderOnlineThresholdSeconds = recorderOnlineThresholdSeconds
        self.recorders = recorders
        self.beds = beds
        self.devices = devices
        self.filters = filters
        self.proxyConnections = proxyConnections
        self.anomalies = anomalies
    }
}
