import Foundation

public struct RuntimeAuditProxyStatusDocument: Codable, Equatable, Sendable {
    public let activeWebSockets: Int
    public let httpRequests: Int
    public let socketIoEventsSeen: Int
    public let socketIoParseFailures: Int
    public let auditWriteFailures: Int
    public let auditFileWriteFailures: Int
    public let auditStdoutWriteFailures: Int
    public let redisIpWriteFailures: Int

    public init(
        activeWebSockets: Int = 0,
        httpRequests: Int = 0,
        socketIoEventsSeen: Int = 0,
        socketIoParseFailures: Int = 0,
        auditWriteFailures: Int = 0,
        auditFileWriteFailures: Int = 0,
        auditStdoutWriteFailures: Int = 0,
        redisIpWriteFailures: Int = 0
    ) {
        self.activeWebSockets = activeWebSockets
        self.httpRequests = httpRequests
        self.socketIoEventsSeen = socketIoEventsSeen
        self.socketIoParseFailures = socketIoParseFailures
        self.auditWriteFailures = auditWriteFailures
        self.auditFileWriteFailures = auditFileWriteFailures
        self.auditStdoutWriteFailures = auditStdoutWriteFailures
        self.redisIpWriteFailures = redisIpWriteFailures
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
