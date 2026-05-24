import Foundation

public struct RuntimeAuditProxyStatusDocument: Codable, Equatable, Sendable {
    public let activeWebSockets: Int
    public let activeRecorderConnections: Int
    public let recorders: [RuntimeRecorderConnectionObservation]
    public let httpRequests: Int
    public let socketIoEventsSeen: Int
    public let socketIoParseFailures: Int
    public let auditWriteFailures: Int
    public let auditFileWriteFailures: Int
    public let auditStdoutWriteFailures: Int
    public let redisIpWriteFailures: Int

    public init(
        activeWebSockets: Int = 0,
        activeRecorderConnections: Int = 0,
        recorders: [RuntimeRecorderConnectionObservation] = [],
        httpRequests: Int = 0,
        socketIoEventsSeen: Int = 0,
        socketIoParseFailures: Int = 0,
        auditWriteFailures: Int = 0,
        auditFileWriteFailures: Int = 0,
        auditStdoutWriteFailures: Int = 0,
        redisIpWriteFailures: Int = 0
    ) {
        self.activeWebSockets = activeWebSockets
        self.activeRecorderConnections = activeRecorderConnections
        self.recorders = recorders
        self.httpRequests = httpRequests
        self.socketIoEventsSeen = socketIoEventsSeen
        self.socketIoParseFailures = socketIoParseFailures
        self.auditWriteFailures = auditWriteFailures
        self.auditFileWriteFailures = auditFileWriteFailures
        self.auditStdoutWriteFailures = auditStdoutWriteFailures
        self.redisIpWriteFailures = redisIpWriteFailures
    }

    enum CodingKeys: String, CodingKey {
        case activeWebSockets
        case activeRecorderConnections
        case recorders
        case httpRequests
        case socketIoEventsSeen
        case socketIoParseFailures
        case auditWriteFailures
        case auditFileWriteFailures
        case auditStdoutWriteFailures
        case redisIpWriteFailures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.activeWebSockets = try container.decodeIfPresent(Int.self, forKey: .activeWebSockets) ?? 0
        self.activeRecorderConnections = try container.decodeIfPresent(Int.self, forKey: .activeRecorderConnections) ?? 0
        self.recorders = try container.decodeIfPresent([RuntimeRecorderConnectionObservation].self, forKey: .recorders) ?? []
        self.httpRequests = try container.decodeIfPresent(Int.self, forKey: .httpRequests) ?? 0
        self.socketIoEventsSeen = try container.decodeIfPresent(Int.self, forKey: .socketIoEventsSeen) ?? 0
        self.socketIoParseFailures = try container.decodeIfPresent(Int.self, forKey: .socketIoParseFailures) ?? 0
        self.auditWriteFailures = try container.decodeIfPresent(Int.self, forKey: .auditWriteFailures) ?? 0
        self.auditFileWriteFailures = try container.decodeIfPresent(Int.self, forKey: .auditFileWriteFailures) ?? 0
        self.auditStdoutWriteFailures = try container.decodeIfPresent(Int.self, forKey: .auditStdoutWriteFailures) ?? 0
        self.redisIpWriteFailures = try container.decodeIfPresent(Int.self, forKey: .redisIpWriteFailures) ?? 0
    }
}

public struct RuntimeRecorderConnectionObservation: Codable, Equatable, Sendable {
    public let vrcode: String
    public let activeConnections: Int
    public let selectedIp: String?
    public let lastSeenAt: String?

    public init(
        vrcode: String,
        activeConnections: Int,
        selectedIp: String? = nil,
        lastSeenAt: String? = nil
    ) {
        self.vrcode = vrcode
        self.activeConnections = activeConnections
        self.selectedIp = selectedIp
        self.lastSeenAt = lastSeenAt
    }
}

public struct RuntimeContainerServiceObservation: Codable, Equatable, Sendable {
    public let service: String
    public let name: String?
    public let state: String?
    public let health: String?
    public let exitCode: Int?

    public init(
        service: String,
        name: String? = nil,
        state: String? = nil,
        health: String? = nil,
        exitCode: Int? = nil
    ) {
        self.service = service
        self.name = name
        self.state = state
        self.health = health
        self.exitCode = exitCode
    }
}

public struct RuntimeContainerObservation: Codable, Equatable, Sendable {
    public let auditProxyHTTP: String
    public let auditProxyStatus: RuntimeAuditProxyStatusDocument?
    public let runtimeStateUpdatedAt: String?
    public let runtimeStateFileUpdatedAt: String?
    public let containerLogsPresent: Bool
    public let containerLogsBytes: UInt64?
    public let containerLogsUpdatedAt: String?
    public let composeServices: [RuntimeContainerServiceObservation]

    public init(
        auditProxyHTTP: String,
        auditProxyStatus: RuntimeAuditProxyStatusDocument?,
        runtimeStateUpdatedAt: String? = nil,
        runtimeStateFileUpdatedAt: String? = nil,
        containerLogsPresent: Bool,
        containerLogsBytes: UInt64?,
        containerLogsUpdatedAt: String? = nil,
        composeServices: [RuntimeContainerServiceObservation] = []
    ) {
        self.auditProxyHTTP = auditProxyHTTP
        self.auditProxyStatus = auditProxyStatus
        self.runtimeStateUpdatedAt = runtimeStateUpdatedAt
        self.runtimeStateFileUpdatedAt = runtimeStateFileUpdatedAt
        self.containerLogsPresent = containerLogsPresent
        self.containerLogsBytes = containerLogsBytes
        self.containerLogsUpdatedAt = containerLogsUpdatedAt
        self.composeServices = composeServices
    }
}
