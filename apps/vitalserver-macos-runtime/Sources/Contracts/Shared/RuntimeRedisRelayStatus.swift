public struct RuntimeRedisRelayBatch: Codable, Equatable, Sendable {
    public var scanned: Int
    public var copied: Int
    public var published: Int
    public var unchanged: Int
    public var duplicates: Int
    public var skipped: Int
    public var denied: Int
    public var missing: Int
    public var errors: Int

    public init(
        scanned: Int = 0,
        copied: Int = 0,
        published: Int = 0,
        unchanged: Int = 0,
        duplicates: Int = 0,
        skipped: Int = 0,
        denied: Int = 0,
        missing: Int = 0,
        errors: Int = 0
    ) {
        self.scanned = scanned
        self.copied = copied
        self.published = published
        self.unchanged = unchanged
        self.duplicates = duplicates
        self.skipped = skipped
        self.denied = denied
        self.missing = missing
        self.errors = errors
    }

    enum CodingKeys: String, CodingKey {
        case scanned
        case copied
        case published
        case unchanged
        case duplicates
        case skipped
        case denied
        case missing
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scanned: try container.decode(Int.self, forKey: .scanned),
            copied: try container.decode(Int.self, forKey: .copied),
            published: try container.decode(Int.self, forKey: .published),
            unchanged: try container.decode(Int.self, forKey: .unchanged),
            duplicates: try container.decode(Int.self, forKey: .duplicates),
            skipped: try container.decode(Int.self, forKey: .skipped),
            denied: try container.decode(Int.self, forKey: .denied),
            missing: try container.decode(Int.self, forKey: .missing),
            errors: try container.decode(Int.self, forKey: .errors)
        )
    }
}

public struct RuntimeRedisRelayStatus: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var observedAt: String
    public var enabled: Bool
    public var state: String
    public var scope: String
    public var targetUrl: String?
    public var targetUsernameConfigured: Bool
    public var targetPasswordConfigured: Bool
    public var settingsFingerprint: String?
    public var batches: Int
    public var totals: RuntimeRedisRelayBatch
    public var lastBatch: RuntimeRedisRelayBatch?
    public var lastSuccessAt: String?
    public var lastErrorAt: String?
    public var lastError: String?

    public init(
        schemaVersion: Int = 1,
        observedAt: String,
        enabled: Bool,
        state: String,
        scope: String,
        targetUrl: String? = nil,
        targetUsernameConfigured: Bool = false,
        targetPasswordConfigured: Bool = false,
        settingsFingerprint: String? = nil,
        batches: Int = 0,
        totals: RuntimeRedisRelayBatch = RuntimeRedisRelayBatch(),
        lastBatch: RuntimeRedisRelayBatch? = nil,
        lastSuccessAt: String? = nil,
        lastErrorAt: String? = nil,
        lastError: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.observedAt = observedAt
        self.enabled = enabled
        self.state = state
        self.scope = scope
        self.targetUrl = targetUrl
        self.targetUsernameConfigured = targetUsernameConfigured
        self.targetPasswordConfigured = targetPasswordConfigured
        self.settingsFingerprint = settingsFingerprint
        self.batches = batches
        self.totals = totals
        self.lastBatch = lastBatch
        self.lastSuccessAt = lastSuccessAt
        self.lastErrorAt = lastErrorAt
        self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case observedAt
        case enabled
        case state
        case scope
        case targetUrl
        case targetUsernameConfigured
        case targetPasswordConfigured
        case settingsFingerprint
        case batches
        case totals
        case lastBatch
        case lastSuccessAt
        case lastErrorAt
        case lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            observedAt: try container.decode(String.self, forKey: .observedAt),
            enabled: try container.decode(Bool.self, forKey: .enabled),
            state: try container.decode(String.self, forKey: .state),
            scope: try container.decode(String.self, forKey: .scope),
            targetUrl: try container.decodeRequiredNullable(String.self, forKey: .targetUrl),
            targetUsernameConfigured: try container.decode(
                Bool.self,
                forKey: .targetUsernameConfigured
            ),
            targetPasswordConfigured: try container.decode(
                Bool.self,
                forKey: .targetPasswordConfigured
            ),
            settingsFingerprint: try container.decodeRequiredNullable(
                String.self,
                forKey: .settingsFingerprint
            ),
            batches: try container.decode(Int.self, forKey: .batches),
            totals: try container.decode(RuntimeRedisRelayBatch.self, forKey: .totals),
            lastBatch: try container.decodeRequiredNullable(RuntimeRedisRelayBatch.self, forKey: .lastBatch),
            lastSuccessAt: try container.decodeRequiredNullable(String.self, forKey: .lastSuccessAt),
            lastErrorAt: try container.decodeRequiredNullable(String.self, forKey: .lastErrorAt),
            lastError: try container.decodeRequiredNullable(String.self, forKey: .lastError)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(state, forKey: .state)
        try container.encode(scope, forKey: .scope)
        try container.encodeNullable(targetUrl, forKey: .targetUrl)
        try container.encode(targetUsernameConfigured, forKey: .targetUsernameConfigured)
        try container.encode(targetPasswordConfigured, forKey: .targetPasswordConfigured)
        try container.encodeNullable(settingsFingerprint, forKey: .settingsFingerprint)
        try container.encode(batches, forKey: .batches)
        try container.encode(totals, forKey: .totals)
        try container.encodeNullable(lastBatch, forKey: .lastBatch)
        try container.encodeNullable(lastSuccessAt, forKey: .lastSuccessAt)
        try container.encodeNullable(lastErrorAt, forKey: .lastErrorAt)
        try container.encodeNullable(lastError, forKey: .lastError)
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredNullable<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Missing required nullable field '\(key.stringValue)'"
                )
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
