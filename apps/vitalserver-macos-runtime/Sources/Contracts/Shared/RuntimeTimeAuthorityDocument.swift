public enum RuntimeTimeAuthorityProfile: String, Codable, Equatable, Sendable {
    case helperNTP = "helper-ntp"
    case enterpriseNTP = "enterprise-ntp"
}

public enum RuntimeClockQualityState: String, Codable, Equatable, Sendable {
    case synchronizing
    case synchronized
    case hostClockOnly = "host-clock-only"
    case unsynchronized
    case stale
    case failed
    case unavailable
}

public struct RuntimeTimeAuthorityDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let profile: RuntimeTimeAuthorityProfile
    public let sourceId: String
    public let serverAddress: String?
    public let serverPort: Int?
    public let state: RuntimeClockQualityState
    public let stratum: Int?
    public let allowedClientAddress: String?
    public let updatedAt: String
    public let issue: String?

    public init(
        schemaVersion: Int = 1,
        profile: RuntimeTimeAuthorityProfile,
        sourceId: String,
        serverAddress: String?,
        serverPort: Int?,
        state: RuntimeClockQualityState,
        stratum: Int?,
        allowedClientAddress: String?,
        updatedAt: String,
        issue: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.sourceId = sourceId
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.state = state
        self.stratum = stratum
        self.allowedClientAddress = allowedClientAddress
        self.updatedAt = updatedAt
        self.issue = issue
    }
}

public struct RuntimeClockQualityDocument: Codable, Equatable, Sendable {
    public let state: RuntimeClockQualityState
    public let observedAt: String
    public let source: String?
    public let stratum: Int?
    public let offsetMs: Double?
    public let uncertaintyMs: Double?
    public let rootDelayMs: Double?
    public let rootDispersionMs: Double?
    public let lastSyncAt: String?
    public let issue: String?

    public init(
        state: RuntimeClockQualityState,
        observedAt: String,
        source: String? = nil,
        stratum: Int? = nil,
        offsetMs: Double? = nil,
        uncertaintyMs: Double? = nil,
        rootDelayMs: Double? = nil,
        rootDispersionMs: Double? = nil,
        lastSyncAt: String? = nil,
        issue: String? = nil
    ) {
        self.state = state
        self.observedAt = observedAt
        self.source = source
        self.stratum = stratum
        self.offsetMs = offsetMs
        self.uncertaintyMs = uncertaintyMs
        self.rootDelayMs = rootDelayMs
        self.rootDispersionMs = rootDispersionMs
        self.lastSyncAt = lastSyncAt
        self.issue = issue
    }
}
