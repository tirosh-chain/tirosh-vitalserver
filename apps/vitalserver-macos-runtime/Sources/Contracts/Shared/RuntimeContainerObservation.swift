import Foundation

public struct RuntimeRecorderIngressStatusDocument: Codable, Equatable, Sendable {
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
    public let failureLogWriteFailures: Int
    public let redisIpWriteFailures: Int
    public let redisIpVerifyFailures: Int
    public let redisIpVerifyMismatches: Int
    public let throughput: RuntimeRecorderIngressThroughputStatus?
    public let rawArchive: RuntimeRecorderIngressRawArchiveStatus?
    public let spool: RuntimeRecorderIngressSpoolStatus?
    public let replay: RuntimeRecorderIngressReplayStatus?

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
        failureLogWriteFailures: Int = 0,
        redisIpWriteFailures: Int = 0,
        redisIpVerifyFailures: Int = 0,
        redisIpVerifyMismatches: Int = 0,
        throughput: RuntimeRecorderIngressThroughputStatus? = nil,
        rawArchive: RuntimeRecorderIngressRawArchiveStatus? = nil,
        spool: RuntimeRecorderIngressSpoolStatus? = nil,
        replay: RuntimeRecorderIngressReplayStatus? = nil
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
        self.failureLogWriteFailures = failureLogWriteFailures
        self.redisIpWriteFailures = redisIpWriteFailures
        self.redisIpVerifyFailures = redisIpVerifyFailures
        self.redisIpVerifyMismatches = redisIpVerifyMismatches
        self.throughput = throughput
        self.rawArchive = rawArchive
        self.spool = spool
        self.replay = replay
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
        case failureLogWriteFailures
        case redisIpWriteFailures
        case redisIpVerifyFailures
        case redisIpVerifyMismatches
        case throughput
        case rawArchive
        case spool
        case replay
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
        self.failureLogWriteFailures = try container.decodeIfPresent(Int.self, forKey: .failureLogWriteFailures) ?? 0
        self.redisIpWriteFailures = try container.decodeIfPresent(Int.self, forKey: .redisIpWriteFailures) ?? 0
        self.redisIpVerifyFailures = try container.decodeIfPresent(Int.self, forKey: .redisIpVerifyFailures) ?? 0
        self.redisIpVerifyMismatches = try container.decodeIfPresent(Int.self, forKey: .redisIpVerifyMismatches) ?? 0
        self.throughput = try container.decodeIfPresent(
            RuntimeRecorderIngressThroughputStatus.self,
            forKey: .throughput
        )
        self.rawArchive = try container.decodeIfPresent(
            RuntimeRecorderIngressRawArchiveStatus.self,
            forKey: .rawArchive
        )
        self.spool = try container.decodeIfPresent(RuntimeRecorderIngressSpoolStatus.self, forKey: .spool)
        self.replay = try container.decodeIfPresent(RuntimeRecorderIngressReplayStatus.self, forKey: .replay)
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
        try container.encode(failureLogWriteFailures, forKey: .failureLogWriteFailures)
        try container.encode(redisIpWriteFailures, forKey: .redisIpWriteFailures)
        try container.encode(redisIpVerifyFailures, forKey: .redisIpVerifyFailures)
        try container.encode(redisIpVerifyMismatches, forKey: .redisIpVerifyMismatches)
        try container.encodeIfPresent(throughput, forKey: .throughput)
        try container.encodeIfPresent(rawArchive, forKey: .rawArchive)
        try container.encodeIfPresent(spool, forKey: .spool)
        try container.encodeIfPresent(replay, forKey: .replay)
    }
}

public struct RuntimeRecorderIngressThroughputStatus: Codable, Equatable, Sendable {
    public let windowSeconds: Int?
    public let observedBytesPerSecond: Double?
    public let spooledBytesPerSecond: Double?
    public let replayedBytesPerSecond: Double?
    public let queueGrowthBytesPerSecond: Double?

    public init(
        windowSeconds: Int? = nil,
        observedBytesPerSecond: Double? = nil,
        spooledBytesPerSecond: Double? = nil,
        replayedBytesPerSecond: Double? = nil,
        queueGrowthBytesPerSecond: Double? = nil
    ) {
        self.windowSeconds = windowSeconds
        self.observedBytesPerSecond = observedBytesPerSecond
        self.spooledBytesPerSecond = spooledBytesPerSecond
        self.replayedBytesPerSecond = replayedBytesPerSecond
        self.queueGrowthBytesPerSecond = queueGrowthBytesPerSecond
    }
}

public struct RuntimeRecorderIngressRawArchiveStatus: Codable, Equatable, Sendable {
    public let status: String?
    public let path: String?
    public let persistedEvents: Int?
    public let persistedBytes: Int?
    public let writeFailures: Int?
    public let lastArchivedAt: String?
    public let lastArchiveId: String?
    public let lastOffset: Int?
    public let lastFailure: RuntimeRecorderIngressFailureObservation?

    public init(
        status: String? = nil,
        path: String? = nil,
        persistedEvents: Int? = nil,
        persistedBytes: Int? = nil,
        writeFailures: Int? = nil,
        lastArchivedAt: String? = nil,
        lastArchiveId: String? = nil,
        lastOffset: Int? = nil,
        lastFailure: RuntimeRecorderIngressFailureObservation? = nil
    ) {
        self.status = status
        self.path = path
        self.persistedEvents = persistedEvents
        self.persistedBytes = persistedBytes
        self.writeFailures = writeFailures
        self.lastArchivedAt = lastArchivedAt
        self.lastArchiveId = lastArchiveId
        self.lastOffset = lastOffset
        self.lastFailure = lastFailure
    }
}

public struct RuntimeRecorderIngressFailureObservation: Codable, Equatable, Sendable {
    public let reason: String?
    public let message: String?
    public let occurredAt: String?

    public init(
        reason: String? = nil,
        message: String? = nil,
        occurredAt: String? = nil
    ) {
        self.reason = reason
        self.message = message
        self.occurredAt = occurredAt
    }
}

public struct RuntimeRecorderIngressSpoolStatus: Codable, Equatable, Sendable {
    public let mode: String?
    public let status: String?
    public let storage: String?
    public let acceptedEvents: Int?
    public let spooledEvents: Int?
    public let skippedRealtimeEvents: Int?
    public let rejectedEvents: Int?
    public let writeFailures: Int?
    public let pendingItems: Int?
    public let pendingBytes: Int?
    public let oldestPendingAgeSeconds: Int?
    public let lastAcceptedAt: String?
    public let lastSpooledAt: String?
    public let lastFailure: RuntimeRecorderIngressFailureObservation?

    public init(
        mode: String? = nil,
        status: String? = nil,
        storage: String? = nil,
        acceptedEvents: Int? = nil,
        spooledEvents: Int? = nil,
        skippedRealtimeEvents: Int? = nil,
        rejectedEvents: Int? = nil,
        writeFailures: Int? = nil,
        pendingItems: Int? = nil,
        pendingBytes: Int? = nil,
        oldestPendingAgeSeconds: Int? = nil,
        lastAcceptedAt: String? = nil,
        lastSpooledAt: String? = nil,
        lastFailure: RuntimeRecorderIngressFailureObservation? = nil
    ) {
        self.mode = mode
        self.status = status
        self.storage = storage
        self.acceptedEvents = acceptedEvents
        self.spooledEvents = spooledEvents
        self.skippedRealtimeEvents = skippedRealtimeEvents
        self.rejectedEvents = rejectedEvents
        self.writeFailures = writeFailures
        self.pendingItems = pendingItems
        self.pendingBytes = pendingBytes
        self.oldestPendingAgeSeconds = oldestPendingAgeSeconds
        self.lastAcceptedAt = lastAcceptedAt
        self.lastSpooledAt = lastSpooledAt
        self.lastFailure = lastFailure
    }
}

public struct RuntimeRecorderIngressReplayStatus: Codable, Equatable, Sendable {
    public let status: String?
    public let pendingItems: Int?
    public let inFlightItems: Int?
    public let replayedEvents: Int?
    public let retryableFailures: Int?
    public let deadLetteredEvents: Int?
    public let replayLagSeconds: Int?
    public let maxBytesPerSecond: Int?
    public let configuredMaxBytesPerSecond: Int?
    public let adaptive: RuntimeRecorderIngressReplayAdaptiveStatus?
    public let lastReplayAt: String?
    public let lastFailure: RuntimeRecorderIngressFailureObservation?

    public init(
        status: String? = nil,
        pendingItems: Int? = nil,
        inFlightItems: Int? = nil,
        replayedEvents: Int? = nil,
        retryableFailures: Int? = nil,
        deadLetteredEvents: Int? = nil,
        replayLagSeconds: Int? = nil,
        maxBytesPerSecond: Int? = nil,
        configuredMaxBytesPerSecond: Int? = nil,
        adaptive: RuntimeRecorderIngressReplayAdaptiveStatus? = nil,
        lastReplayAt: String? = nil,
        lastFailure: RuntimeRecorderIngressFailureObservation? = nil
    ) {
        self.status = status
        self.pendingItems = pendingItems
        self.inFlightItems = inFlightItems
        self.replayedEvents = replayedEvents
        self.retryableFailures = retryableFailures
        self.deadLetteredEvents = deadLetteredEvents
        self.replayLagSeconds = replayLagSeconds
        self.maxBytesPerSecond = maxBytesPerSecond
        self.configuredMaxBytesPerSecond = configuredMaxBytesPerSecond
        self.adaptive = adaptive
        self.lastReplayAt = lastReplayAt
        self.lastFailure = lastFailure
    }
}

public enum RuntimeRecorderIngressMemoryGuardStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case healthy
    case warm
    case hot
    case critical
    case missing
    case stale
    case invalid
    case failed
    case unavailable
    case disabled
}

public struct RuntimeRecorderIngressReplayAdaptiveStatus: Codable, Equatable, Sendable {
    public let enabled: Bool?
    public let minBytesPerSecond: Int?
    public let maxBytesPerSecond: Int?
    public let currentMaxBytesPerSecond: Int?
    public let minItemsPerTick: Int?
    public let maxItemsPerTick: Int?
    public let currentItemsPerTick: Int?
    public let minConcurrency: Int?
    public let maxConcurrency: Int?
    public let currentConcurrency: Int?
    public let lastDecision: String?
    public let lastReason: String?
    public let lastChangedAt: String?
    public let memoryGuardStatus: RuntimeRecorderIngressMemoryGuardStatus?

    public init(
        enabled: Bool? = nil,
        minBytesPerSecond: Int? = nil,
        maxBytesPerSecond: Int? = nil,
        currentMaxBytesPerSecond: Int? = nil,
        minItemsPerTick: Int? = nil,
        maxItemsPerTick: Int? = nil,
        currentItemsPerTick: Int? = nil,
        minConcurrency: Int? = nil,
        maxConcurrency: Int? = nil,
        currentConcurrency: Int? = nil,
        lastDecision: String? = nil,
        lastReason: String? = nil,
        lastChangedAt: String? = nil,
        memoryGuardStatus: RuntimeRecorderIngressMemoryGuardStatus? = nil
    ) {
        self.enabled = enabled
        self.minBytesPerSecond = minBytesPerSecond
        self.maxBytesPerSecond = maxBytesPerSecond
        self.currentMaxBytesPerSecond = currentMaxBytesPerSecond
        self.minItemsPerTick = minItemsPerTick
        self.maxItemsPerTick = maxItemsPerTick
        self.currentItemsPerTick = currentItemsPerTick
        self.minConcurrency = minConcurrency
        self.maxConcurrency = maxConcurrency
        self.currentConcurrency = currentConcurrency
        self.lastDecision = lastDecision
        self.lastReason = lastReason
        self.lastChangedAt = lastChangedAt
        self.memoryGuardStatus = memoryGuardStatus
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
    public let spool: RuntimeRecorderIngressSpoolStatus?
    public let replay: RuntimeRecorderIngressReplayStatus?

    public init(
        vrcode: String,
        activeConnections: Int,
        selectedIp: String? = nil,
        ipSource: String? = nil,
        lastSeenAt: String? = nil,
        redisIpSync: RuntimeRecorderRedisIPSyncObservation? = nil,
        spool: RuntimeRecorderIngressSpoolStatus? = nil,
        replay: RuntimeRecorderIngressReplayStatus? = nil
    ) {
        self.vrcode = vrcode
        self.activeConnections = activeConnections
        self.selectedIp = selectedIp
        self.ipSource = ipSource
        self.lastSeenAt = lastSeenAt
        self.redisIpSync = redisIpSync
        self.spool = spool
        self.replay = replay
    }
}

public struct RuntimeContainerServiceObservation: Codable, Equatable, Sendable {
    public let service: String
    public let containerID: String?
    public let name: String?
    public let state: String?
    public let health: String?
    public let exitCode: Int?
    public let error: String?
    public let finishedAt: String?
    public let memoryUsedBytes: Int?
    public let memoryLimitBytes: Int?
    public let oomKilled: Bool?
    public let restartCount: Int?
    public let startedAt: String?
    public let uptimeSeconds: Int?

    public init(
        service: String,
        containerID: String? = nil,
        name: String? = nil,
        state: String? = nil,
        health: String? = nil,
        exitCode: Int? = nil,
        error: String? = nil,
        finishedAt: String? = nil,
        memoryUsedBytes: Int? = nil,
        memoryLimitBytes: Int? = nil,
        oomKilled: Bool? = nil,
        restartCount: Int? = nil,
        startedAt: String? = nil,
        uptimeSeconds: Int? = nil
    ) {
        self.service = service
        self.containerID = containerID
        self.name = name
        self.state = state
        self.health = health
        self.exitCode = exitCode
        self.error = error
        self.finishedAt = finishedAt
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.oomKilled = oomKilled
        self.restartCount = restartCount
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
    public let recorderIngressHTTP: String
    public let recorderIngressStatus: RuntimeRecorderIngressStatusDocument?
    public let recorderIngressStatusReadState: RuntimeRecorderIngressStatusReadState
    public let recorderIngressStatusReadError: String?
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
        recorderIngressHTTP: String,
        recorderIngressStatus: RuntimeRecorderIngressStatusDocument?,
        recorderIngressStatusReadState: RuntimeRecorderIngressStatusReadState? = nil,
        recorderIngressStatusReadError: String? = nil,
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
        self.recorderIngressHTTP = recorderIngressHTTP
        self.recorderIngressStatus = recorderIngressStatus
        self.recorderIngressStatusReadState = recorderIngressStatusReadState
            ?? RuntimeRecorderIngressStatusReadResult(
                httpStatus: recorderIngressHTTP,
                document: recorderIngressStatus,
                readError: recorderIngressStatusReadError
            ).readState
        self.recorderIngressStatusReadError = recorderIngressStatusReadError
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
        case recorderIngressHTTP
        case recorderIngressStatus
        case recorderIngressStatusReadState
        case recorderIngressStatusReadError
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
        self.recorderIngressHTTP = try container.decode(String.self, forKey: .recorderIngressHTTP)
        self.recorderIngressStatus = try container.decodeIfPresent(
            RuntimeRecorderIngressStatusDocument.self,
            forKey: .recorderIngressStatus
        )
        self.recorderIngressStatusReadError = try container.decodeIfPresent(
            String.self,
            forKey: .recorderIngressStatusReadError
        )
        self.recorderIngressStatusReadState = try container.decodeIfPresent(
            RuntimeRecorderIngressStatusReadState.self,
            forKey: .recorderIngressStatusReadState
        ) ?? RuntimeRecorderIngressStatusReadResult(
            httpStatus: recorderIngressHTTP,
            document: recorderIngressStatus,
            readError: recorderIngressStatusReadError
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
