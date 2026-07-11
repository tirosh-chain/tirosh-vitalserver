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
