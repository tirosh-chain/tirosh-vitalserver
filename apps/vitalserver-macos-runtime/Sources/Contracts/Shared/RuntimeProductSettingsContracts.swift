import Foundation

public enum RuntimeProductSettingsReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
}

public struct RuntimeProductSettingsRead: Codable, Equatable, Sendable {
    public let state: RuntimeProductSettingsReadState
    public let settings: GuestRuntimeSettingsDocument?
    public let readError: String?

    public init(
        state: RuntimeProductSettingsReadState,
        settings: GuestRuntimeSettingsDocument?,
        readError: String?
    ) {
        self.state = state
        self.settings = settings
        self.readError = readError
    }

    private enum CodingKeys: String, CodingKey {
        case state, settings, readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.settings) else {
            throw DecodingError.keyNotFound(
                CodingKeys.settings,
                .init(codingPath: decoder.codingPath, debugDescription: "Runtime product settings read requires explicit settings")
            )
        }
        guard container.contains(.readError) else {
            throw DecodingError.keyNotFound(
                CodingKeys.readError,
                .init(codingPath: decoder.codingPath, debugDescription: "Runtime product settings read requires explicit readError")
            )
        }
        self.init(
            state: try container.decode(RuntimeProductSettingsReadState.self, forKey: .state),
            settings: try container.decodeIfPresent(GuestRuntimeSettingsDocument.self, forKey: .settings),
            readError: try container.decodeIfPresent(String.self, forKey: .readError)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let settings {
            try container.encode(settings, forKey: .settings)
        } else {
            try container.encodeNil(forKey: .settings)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public struct RuntimeApplyProductSettingsRequest: Codable, Equatable, Sendable {
    public let settings: GuestRuntimeSettingsDocument

    public init(settings: GuestRuntimeSettingsDocument) {
        self.settings = settings
    }
}

public struct RuntimeAdminPasswordRequest: Codable, Equatable, Sendable {
    public let password: String

    public init(password: String) {
        self.password = password
    }
}

public struct RuntimeRedisRelayTargetRead: Codable, Equatable, Sendable {
    public let url: String
    public let username: String
    public let passwordConfigured: Bool
    public let tls: Bool

    public init(url: String, username: String, passwordConfigured: Bool, tls: Bool) {
        self.url = url
        self.username = username
        self.passwordConfigured = passwordConfigured
        self.tls = tls
    }
}

public struct RuntimeRedisRelayTargetApply: Codable, Equatable, Sendable {
    public let url: String
    public let username: String
    public let password: String?
    public let clearPassword: Bool
    public let tls: Bool

    public init(url: String, username: String, password: String?, clearPassword: Bool, tls: Bool) {
        self.url = url
        self.username = username
        self.password = password
        self.clearPassword = clearPassword
        self.tls = tls
    }
}

public enum RuntimeRedisRelaySettingsScope: String, Codable, Equatable, Sendable {
    case waveformTrendOnly = "waveform_trend_only"
    case vitalReconstruction = "vital_reconstruction"
}

public struct RuntimeRedisRelaySettingsReadDocument: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let target: RuntimeRedisRelayTargetRead
    public let scope: RuntimeRedisRelaySettingsScope
    public let includeRecorderNetworkContext: Bool
    public let intervalSeconds: Double
    public let scanCount: Int

    public init(enabled: Bool, target: RuntimeRedisRelayTargetRead, scope: RuntimeRedisRelaySettingsScope, includeRecorderNetworkContext: Bool, intervalSeconds: Double, scanCount: Int) {
        self.enabled = enabled
        self.target = target
        self.scope = scope
        self.includeRecorderNetworkContext = includeRecorderNetworkContext
        self.intervalSeconds = intervalSeconds
        self.scanCount = scanCount
    }
}

public struct RuntimeRedisRelaySettingsRead: Codable, Equatable, Sendable {
    public let state: RuntimeProductSettingsReadState
    public let settings: RuntimeRedisRelaySettingsReadDocument?
    public let readError: String?

    public init(state: RuntimeProductSettingsReadState, settings: RuntimeRedisRelaySettingsReadDocument?, readError: String?) {
        self.state = state
        self.settings = settings
        self.readError = readError
    }

    private enum CodingKeys: String, CodingKey {
        case state, settings, readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.settings, .readError] where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Redis Relay settings read requires explicit nullable field \(key.stringValue)."
                )
            )
        }
        state = try container.decode(RuntimeProductSettingsReadState.self, forKey: .state)
        settings = try container.decodeIfPresent(RuntimeRedisRelaySettingsReadDocument.self, forKey: .settings)
        readError = try container.decodeIfPresent(String.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let settings {
            try container.encode(settings, forKey: .settings)
        } else {
            try container.encodeNil(forKey: .settings)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public struct RuntimeRedisRelaySettingsApplyRequest: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let target: RuntimeRedisRelayTargetApply
    public let scope: RuntimeRedisRelaySettingsScope
    public let includeRecorderNetworkContext: Bool
    public let intervalSeconds: Double
    public let scanCount: Int

    public init(enabled: Bool, target: RuntimeRedisRelayTargetApply, scope: RuntimeRedisRelaySettingsScope, includeRecorderNetworkContext: Bool, intervalSeconds: Double, scanCount: Int) {
        self.enabled = enabled
        self.target = target
        self.scope = scope
        self.includeRecorderNetworkContext = includeRecorderNetworkContext
        self.intervalSeconds = intervalSeconds
        self.scanCount = scanCount
    }
}
