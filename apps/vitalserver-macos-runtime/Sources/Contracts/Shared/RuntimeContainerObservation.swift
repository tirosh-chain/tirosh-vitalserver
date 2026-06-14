import Foundation

public struct RuntimeAuditProxyStatusDocument: Codable, Equatable, Sendable {
    public let startedAt: String?
    public let uptimeSeconds: Int?
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
    public let redisIpVerifyFailures: Int
    public let redisIpVerifyMismatches: Int

    public init(
        startedAt: String? = nil,
        uptimeSeconds: Int? = nil,
        activeWebSockets: Int = 0,
        activeRecorderConnections: Int = 0,
        recorders: [RuntimeRecorderConnectionObservation] = [],
        httpRequests: Int = 0,
        socketIoEventsSeen: Int = 0,
        socketIoParseFailures: Int = 0,
        auditWriteFailures: Int = 0,
        auditFileWriteFailures: Int = 0,
        auditStdoutWriteFailures: Int = 0,
        redisIpWriteFailures: Int = 0,
        redisIpVerifyFailures: Int = 0,
        redisIpVerifyMismatches: Int = 0
    ) {
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
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
        self.redisIpVerifyFailures = redisIpVerifyFailures
        self.redisIpVerifyMismatches = redisIpVerifyMismatches
    }

    enum CodingKeys: String, CodingKey {
        case startedAt
        case uptimeSeconds
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
        case redisIpVerifyFailures
        case redisIpVerifyMismatches
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        self.uptimeSeconds = try container.decodeIfPresent(Int.self, forKey: .uptimeSeconds)
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
        self.redisIpVerifyFailures = try container.decodeIfPresent(Int.self, forKey: .redisIpVerifyFailures) ?? 0
        self.redisIpVerifyMismatches = try container.decodeIfPresent(Int.self, forKey: .redisIpVerifyMismatches) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(uptimeSeconds, forKey: .uptimeSeconds)
        try container.encode(activeWebSockets, forKey: .activeWebSockets)
        try container.encode(activeRecorderConnections, forKey: .activeRecorderConnections)
        try container.encode(recorders, forKey: .recorders)
        try container.encode(httpRequests, forKey: .httpRequests)
        try container.encode(socketIoEventsSeen, forKey: .socketIoEventsSeen)
        try container.encode(socketIoParseFailures, forKey: .socketIoParseFailures)
        try container.encode(auditWriteFailures, forKey: .auditWriteFailures)
        try container.encode(auditFileWriteFailures, forKey: .auditFileWriteFailures)
        try container.encode(auditStdoutWriteFailures, forKey: .auditStdoutWriteFailures)
        try container.encode(redisIpWriteFailures, forKey: .redisIpWriteFailures)
        try container.encode(redisIpVerifyFailures, forKey: .redisIpVerifyFailures)
        try container.encode(redisIpVerifyMismatches, forKey: .redisIpVerifyMismatches)
    }
}

public enum RuntimeRecorderRedisIPSyncStatus: String, Codable, Equatable, Sendable {
    case unknown
    case unavailable
    case disabled
    case pending
    case written
    case correcting
    case corrected
    case verified
    case mismatch
    case writeFailed = "write_failed"
    case verifyFailed = "verify_failed"
}

public struct RuntimeRecorderRedisIPSyncObservation: Codable, Equatable, Sendable {
    public let status: RuntimeRecorderRedisIPSyncStatus
    public let redisKey: String?
    public let selectedIp: String?
    public let ipSource: String?
    public let redisValue: String?
    public let lastWriteAt: String?
    public let lastVerifiedAt: String?
    public let lastFailure: String?

    public init(
        status: RuntimeRecorderRedisIPSyncStatus,
        redisKey: String? = nil,
        selectedIp: String? = nil,
        ipSource: String? = nil,
        redisValue: String? = nil,
        lastWriteAt: String? = nil,
        lastVerifiedAt: String? = nil,
        lastFailure: String? = nil
    ) {
        self.status = status
        self.redisKey = redisKey
        self.selectedIp = selectedIp
        self.ipSource = ipSource
        self.redisValue = redisValue
        self.lastWriteAt = lastWriteAt
        self.lastVerifiedAt = lastVerifiedAt
        self.lastFailure = lastFailure
    }
}

public struct RuntimeRecorderConnectionObservation: Codable, Equatable, Sendable {
    public let vrcode: String
    public let activeConnections: Int
    public let selectedIp: String?
    public let ipSource: String?
    public let lastSeenAt: String?
    public let redisIpSync: RuntimeRecorderRedisIPSyncObservation?

    public init(
        vrcode: String,
        activeConnections: Int,
        selectedIp: String? = nil,
        ipSource: String? = nil,
        lastSeenAt: String? = nil,
        redisIpSync: RuntimeRecorderRedisIPSyncObservation? = nil
    ) {
        self.vrcode = vrcode
        self.activeConnections = activeConnections
        self.selectedIp = selectedIp
        self.ipSource = ipSource
        self.lastSeenAt = lastSeenAt
        self.redisIpSync = redisIpSync
    }
}

public struct RuntimeContainerServiceObservation: Codable, Equatable, Sendable {
    public let service: String
    public let name: String?
    public let state: String?
    public let health: String?
    public let exitCode: Int?
    public let startedAt: String?
    public let uptimeSeconds: Int?

    public init(
        service: String,
        name: String? = nil,
        state: String? = nil,
        health: String? = nil,
        exitCode: Int? = nil,
        startedAt: String? = nil,
        uptimeSeconds: Int? = nil
    ) {
        self.service = service
        self.name = name
        self.state = state
        self.health = health
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
    }
}

public enum RuntimeContainerServicesReadState: String, Codable, Equatable, Sendable {
    case loaded
    case missing
    case invalid
    case stale
    case readFailed = "read-failed"
}

public struct RuntimeContainerObservation: Codable, Equatable, Sendable {
    public let auditProxyHTTP: String
    public let auditProxyStatus: RuntimeAuditProxyStatusDocument?
    public let auditProxyStatusReadState: RuntimeAuditProxyStatusReadState
    public let auditProxyStatusReadError: String?
    public let runtimeStateUpdatedAt: String?
    public let runtimeStateFileUpdatedAt: String?
    public let runtimeStateFileMetadataReadState: RuntimeFileMetadataReadState
    public let runtimeStateFileMetadataError: String?
    public let containerLogsPresent: Bool
    public let containerLogsBytes: UInt64?
    public let containerLogsUpdatedAt: String?
    public let containerLogsMetadataError: String?
    public let composeServicesReadState: RuntimeContainerServicesReadState
    public let composeServices: [RuntimeContainerServiceObservation]
    public let composeServicesReadError: String?

    public init(
        auditProxyHTTP: String,
        auditProxyStatus: RuntimeAuditProxyStatusDocument?,
        auditProxyStatusReadState: RuntimeAuditProxyStatusReadState? = nil,
        auditProxyStatusReadError: String? = nil,
        runtimeStateUpdatedAt: String? = nil,
        runtimeStateFileUpdatedAt: String? = nil,
        runtimeStateFileMetadataReadState: RuntimeFileMetadataReadState? = nil,
        runtimeStateFileMetadataError: String? = nil,
        containerLogsPresent: Bool,
        containerLogsBytes: UInt64?,
        containerLogsUpdatedAt: String? = nil,
        containerLogsMetadataError: String? = nil,
        composeServicesReadState: RuntimeContainerServicesReadState? = nil,
        composeServices: [RuntimeContainerServiceObservation] = [],
        composeServicesReadError: String? = nil
    ) {
        self.auditProxyHTTP = auditProxyHTTP
        self.auditProxyStatus = auditProxyStatus
        self.auditProxyStatusReadState = auditProxyStatusReadState
            ?? RuntimeAuditProxyStatusReadResult(
                httpStatus: auditProxyHTTP,
                document: auditProxyStatus,
                readError: auditProxyStatusReadError
            ).readState
        self.auditProxyStatusReadError = auditProxyStatusReadError
        self.runtimeStateUpdatedAt = runtimeStateUpdatedAt
        self.runtimeStateFileUpdatedAt = runtimeStateFileUpdatedAt
        self.runtimeStateFileMetadataReadState = runtimeStateFileMetadataReadState
            ?? RuntimeContainerObservation.metadataReadState(
                updatedAt: runtimeStateFileUpdatedAt,
                readError: runtimeStateFileMetadataError
            )
        self.runtimeStateFileMetadataError = runtimeStateFileMetadataError
        self.containerLogsPresent = containerLogsPresent
        self.containerLogsBytes = containerLogsBytes
        self.containerLogsUpdatedAt = containerLogsUpdatedAt
        self.containerLogsMetadataError = containerLogsMetadataError
        self.composeServicesReadState = RuntimeContainerObservation.composeServicesReadState(
            explicitState: composeServicesReadState,
            readError: composeServicesReadError
        )
        self.composeServices = composeServices
        self.composeServicesReadError = composeServicesReadError
    }

    enum CodingKeys: String, CodingKey {
        case auditProxyHTTP
        case auditProxyStatus
        case auditProxyStatusReadState
        case auditProxyStatusReadError
        case runtimeStateUpdatedAt
        case runtimeStateFileUpdatedAt
        case runtimeStateFileMetadataReadState
        case runtimeStateFileMetadataError
        case containerLogsPresent
        case containerLogsBytes
        case containerLogsUpdatedAt
        case containerLogsMetadataError
        case composeServicesReadState
        case composeServices
        case composeServicesReadError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let composeServicesReadError = try container.decodeIfPresent(
            String.self,
            forKey: .composeServicesReadError
        )
        let composeServices = try container.decodeIfPresent(
            [RuntimeContainerServiceObservation].self,
            forKey: .composeServices
        )
        self.auditProxyHTTP = try container.decode(String.self, forKey: .auditProxyHTTP)
        self.auditProxyStatus = try container.decodeIfPresent(
            RuntimeAuditProxyStatusDocument.self,
            forKey: .auditProxyStatus
        )
        self.auditProxyStatusReadError = try container.decodeIfPresent(
            String.self,
            forKey: .auditProxyStatusReadError
        )
        self.auditProxyStatusReadState = try container.decodeIfPresent(
            RuntimeAuditProxyStatusReadState.self,
            forKey: .auditProxyStatusReadState
        ) ?? RuntimeAuditProxyStatusReadResult(
            httpStatus: auditProxyHTTP,
            document: auditProxyStatus,
            readError: auditProxyStatusReadError
        ).readState
        self.runtimeStateUpdatedAt = try container.decodeIfPresent(String.self, forKey: .runtimeStateUpdatedAt)
        self.runtimeStateFileUpdatedAt = try container.decodeIfPresent(String.self, forKey: .runtimeStateFileUpdatedAt)
        self.runtimeStateFileMetadataError = try container.decodeIfPresent(
            String.self,
            forKey: .runtimeStateFileMetadataError
        )
        self.runtimeStateFileMetadataReadState = try container.decodeIfPresent(
            RuntimeFileMetadataReadState.self,
            forKey: .runtimeStateFileMetadataReadState
        ) ?? RuntimeContainerObservation.metadataReadState(
            updatedAt: runtimeStateFileUpdatedAt,
            readError: runtimeStateFileMetadataError
        )
        self.containerLogsPresent = try container.decode(Bool.self, forKey: .containerLogsPresent)
        self.containerLogsBytes = try container.decodeIfPresent(UInt64.self, forKey: .containerLogsBytes)
        self.containerLogsUpdatedAt = try container.decodeIfPresent(String.self, forKey: .containerLogsUpdatedAt)
        self.containerLogsMetadataError = try container.decodeIfPresent(
            String.self,
            forKey: .containerLogsMetadataError
        )
        self.composeServicesReadState = RuntimeContainerObservation.composeServicesReadState(
            explicitState: try container.decodeIfPresent(
                RuntimeContainerServicesReadState.self,
                forKey: .composeServicesReadState
            ),
            readError: composeServicesReadError,
            servicesKeyPresent: container.contains(.composeServices)
        )
        self.composeServices = composeServices ?? []
        self.composeServicesReadError = composeServicesReadError
    }

    private static func composeServicesReadState(
        explicitState: RuntimeContainerServicesReadState?,
        readError: String?,
        servicesKeyPresent: Bool = true
    ) -> RuntimeContainerServicesReadState {
        if let explicitState {
            return explicitState
        }
        if let readError, !readError.isEmpty {
            return .readFailed
        }
        if servicesKeyPresent {
            return .loaded
        }
        return .missing
    }

    private static func metadataReadState(
        updatedAt: String?,
        readError: String?
    ) -> RuntimeFileMetadataReadState {
        if readError != nil {
            return .readFailed
        }
        if updatedAt != nil {
            return .loaded
        }
        return .notRead
    }
}
