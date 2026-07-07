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
        self.activeWebSockets = try container.decode(Int.self, forKey: .activeWebSockets)
        self.activeRecorderConnections = try container.decode(Int.self, forKey: .activeRecorderConnections)
        self.recorders = try container.decode([RuntimeRecorderConnectionObservation].self, forKey: .recorders)
        self.httpRequests = try container.decode(Int.self, forKey: .httpRequests)
        self.socketIoEventsSeen = try container.decode(Int.self, forKey: .socketIoEventsSeen)
        self.socketIoParseFailures = try container.decode(Int.self, forKey: .socketIoParseFailures)
        self.auditWriteFailures = try container.decode(Int.self, forKey: .auditWriteFailures)
        self.auditFileWriteFailures = try container.decode(Int.self, forKey: .auditFileWriteFailures)
        self.auditStdoutWriteFailures = try container.decode(Int.self, forKey: .auditStdoutWriteFailures)
        self.failureLogWriteFailures = try container.decode(Int.self, forKey: .failureLogWriteFailures)
        self.redisIpWriteFailures = try container.decode(Int.self, forKey: .redisIpWriteFailures)
        self.redisIpVerifyFailures = try container.decode(Int.self, forKey: .redisIpVerifyFailures)
        self.redisIpVerifyMismatches = try container.decode(Int.self, forKey: .redisIpVerifyMismatches)
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

private extension KeyedEncodingContainer {
    mutating func encodeExplicitOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
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
    public let autoExport: RuntimeRecorderIngressRawArchiveAutoExportStatus?

    public init(
        status: String? = nil,
        path: String? = nil,
        persistedEvents: Int? = nil,
        persistedBytes: Int? = nil,
        writeFailures: Int? = nil,
        lastArchivedAt: String? = nil,
        lastArchiveId: String? = nil,
        lastOffset: Int? = nil,
        lastFailure: RuntimeRecorderIngressFailureObservation? = nil,
        autoExport: RuntimeRecorderIngressRawArchiveAutoExportStatus? = nil
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
        self.autoExport = autoExport
    }
}

public struct RuntimeRecorderIngressRawArchiveAutoExportStatus: Codable, Equatable, Sendable {
    public let status: String?
    public let finalizable: Bool?
    public let reasons: [String]?
    public let archivePath: String?
    public let archiveCursor: Int?
    public let cursorStableForMs: Int?
    public let lastDecisionAt: String?
    public let activeJob: RuntimeRecorderIngressRawArchiveAutoExportJob?
    public let uploadedJobs: Int?
    public let failedJobs: Int?
    public let lastResult: RuntimeRecorderIngressRawArchiveAutoExportResult?
    public let lastFailure: RuntimeRecorderIngressFailureObservation?

    public init(
        status: String? = nil,
        finalizable: Bool? = nil,
        reasons: [String]? = nil,
        archivePath: String? = nil,
        archiveCursor: Int? = nil,
        cursorStableForMs: Int? = nil,
        lastDecisionAt: String? = nil,
        activeJob: RuntimeRecorderIngressRawArchiveAutoExportJob? = nil,
        uploadedJobs: Int? = nil,
        failedJobs: Int? = nil,
        lastResult: RuntimeRecorderIngressRawArchiveAutoExportResult? = nil,
        lastFailure: RuntimeRecorderIngressFailureObservation? = nil
    ) {
        self.status = status
        self.finalizable = finalizable
        self.reasons = reasons
        self.archivePath = archivePath
        self.archiveCursor = archiveCursor
        self.cursorStableForMs = cursorStableForMs
        self.lastDecisionAt = lastDecisionAt
        self.activeJob = activeJob
        self.uploadedJobs = uploadedJobs
        self.failedJobs = failedJobs
        self.lastResult = lastResult
        self.lastFailure = lastFailure
    }
}

public struct RuntimeRecorderIngressRawArchiveAutoExportJob: Codable, Equatable, Sendable {
    public let jobId: String?
    public let archivePath: String?
    public let archiveCursor: Int?
    public let state: String?
    public let attempts: Int?
    public let maxAttempts: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let startedAt: String?
    public let completedAt: String?
    public let nextAttemptAt: String?
    public let lastFailure: RuntimeRecorderIngressFailureObservation?

    public init(
        jobId: String? = nil,
        archivePath: String? = nil,
        archiveCursor: Int? = nil,
        state: String? = nil,
        attempts: Int? = nil,
        maxAttempts: Int? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil,
        nextAttemptAt: String? = nil,
        lastFailure: RuntimeRecorderIngressFailureObservation? = nil
    ) {
        self.jobId = jobId
        self.archivePath = archivePath
        self.archiveCursor = archiveCursor
        self.state = state
        self.attempts = attempts
        self.maxAttempts = maxAttempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.nextAttemptAt = nextAttemptAt
        self.lastFailure = lastFailure
    }
}

public struct RuntimeRecorderIngressRawArchiveAutoExportResult: Codable, Equatable, Sendable {
    public let values: [String: RuntimeJSONValue]

    public init(
        values: [String: RuntimeJSONValue] = [:]
    ) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: RuntimeJSONValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

public enum RuntimeJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([RuntimeJSONValue])
    case object([String: RuntimeJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RuntimeJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RuntimeJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
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

    private enum CodingKeys: String, CodingKey {
        case status
        case redisKey
        case selectedIp
        case ipSource
        case redisValue
        case lastWriteAt
        case lastVerifiedAt
        case lastFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(RuntimeRecorderRedisIPSyncStatus.self, forKey: .status),
            redisKey: try container.decodeIfPresent(String.self, forKey: .redisKey),
            selectedIp: try container.decodeIfPresent(String.self, forKey: .selectedIp),
            ipSource: try container.decodeIfPresent(String.self, forKey: .ipSource),
            redisValue: try container.decodeIfPresent(String.self, forKey: .redisValue),
            lastWriteAt: try container.decodeIfPresent(String.self, forKey: .lastWriteAt),
            lastVerifiedAt: try container.decodeIfPresent(String.self, forKey: .lastVerifiedAt),
            lastFailure: try container.decodeIfPresent(String.self, forKey: .lastFailure)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeExplicitOptional(redisKey, forKey: .redisKey)
        try container.encodeExplicitOptional(selectedIp, forKey: .selectedIp)
        try container.encodeExplicitOptional(ipSource, forKey: .ipSource)
        try container.encodeExplicitOptional(redisValue, forKey: .redisValue)
        try container.encodeExplicitOptional(lastWriteAt, forKey: .lastWriteAt)
        try container.encodeExplicitOptional(lastVerifiedAt, forKey: .lastVerifiedAt)
        try container.encodeExplicitOptional(lastFailure, forKey: .lastFailure)
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
