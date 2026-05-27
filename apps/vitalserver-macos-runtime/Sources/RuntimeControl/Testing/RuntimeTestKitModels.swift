import Foundation

public enum RuntimeTestKitState: String, Codable, Equatable, Sendable {
    case disabled
    case stopped
    case starting
    case running
    case stopping
    case failed
}

public enum RuntimeTestKitScenario: String, Codable, CaseIterable, Equatable, Sendable {
    case normal
    case multipleRecorders = "multiple_recorders"
    case burstTraffic = "burst_traffic"
    case disconnectReconnect = "disconnect_reconnect"
    case staleRecorder = "stale_recorder"
    case signalAnomaly = "signal_anomaly"
}

public enum RuntimeTestKitSignalProfile: String, Codable, CaseIterable, Equatable, Sendable {
    case normal
    case tachycardia
    case desaturation
    case artifact
    case deviceDisconnect = "device_disconnect"
}

public struct RuntimeTestKitStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var state: RuntimeTestKitState
    public var serviceName: String?
    public var apiBaseURL: String?
    public var recorderTargetURL: String?
    public var startedAt: Date?
    public var activeSession: RuntimeTestKitSession?
    public var sessions: [RuntimeTestKitSession]
    public var lastError: String?

    public init(
        enabled: Bool,
        state: RuntimeTestKitState,
        serviceName: String? = nil,
        apiBaseURL: String? = nil,
        recorderTargetURL: String? = nil,
        startedAt: Date? = nil,
        activeSession: RuntimeTestKitSession? = nil,
        sessions: [RuntimeTestKitSession] = [],
        lastError: String? = nil
    ) {
        self.enabled = enabled
        self.state = state
        self.serviceName = serviceName
        self.apiBaseURL = apiBaseURL
        self.recorderTargetURL = recorderTargetURL
        self.startedAt = startedAt
        self.activeSession = activeSession
        self.sessions = sessions
        self.lastError = lastError
    }
}

public struct RuntimeTestKitVirtualRecorderStartRequest: Codable, Equatable, Sendable {
    public var targetURL: String
    public var scenario: RuntimeTestKitScenario
    public var signalProfile: RuntimeTestKitSignalProfile
    public var recorders: Int
    public var vrcode: String?
    public var version: String
    public var intervalSeconds: Double
    public var durationSeconds: Double?
    public var maxMessages: Int?
    public var shiftTime: Bool
    public var generateFrames: Bool

    public init(
        targetURL: String,
        scenario: RuntimeTestKitScenario = .normal,
        signalProfile: RuntimeTestKitSignalProfile = .normal,
        recorders: Int = 1,
        vrcode: String? = nil,
        version: String = "testkit",
        intervalSeconds: Double = 1,
        durationSeconds: Double? = nil,
        maxMessages: Int? = nil,
        shiftTime: Bool = true,
        generateFrames: Bool = true
    ) {
        self.targetURL = targetURL
        self.scenario = scenario
        self.signalProfile = signalProfile
        self.recorders = recorders
        self.vrcode = vrcode
        self.version = version
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
        self.maxMessages = maxMessages
        self.shiftTime = shiftTime
        self.generateFrames = generateFrames
    }

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case scenario
        case signalProfile
        case recorders
        case vrcode
        case version
        case intervalSeconds
        case durationSeconds
        case maxMessages
        case shiftTime
        case generateFrames
    }
}

public struct RuntimeTestKitSession: Codable, Equatable, Sendable {
    public var id: String
    public var state: String
    public var targetURL: String
    public var recordersRequested: Int
    public var vrcode: String?
    public var version: String
    public var intervalSeconds: Double
    public var durationSeconds: Double?
    public var maxMessages: Int?
    public var shiftTime: Bool
    public var generateFrames: Bool
    public var defaultScenario: String
    public var createdAt: Double?
    public var startedAt: Double?
    public var stoppedAt: Double?
    public var messagesSent: Int
    public var bytesSent: Int
    public var lastError: String?
    public var recorders: [RuntimeTestKitRecorder]

    public init(
        id: String,
        state: String,
        targetURL: String,
        recordersRequested: Int,
        vrcode: String?,
        version: String,
        intervalSeconds: Double,
        durationSeconds: Double?,
        maxMessages: Int?,
        shiftTime: Bool,
        generateFrames: Bool,
        defaultScenario: String,
        createdAt: Double?,
        startedAt: Double?,
        stoppedAt: Double?,
        messagesSent: Int,
        bytesSent: Int,
        lastError: String?,
        recorders: [RuntimeTestKitRecorder]
    ) {
        self.id = id
        self.state = state
        self.targetURL = targetURL
        self.recordersRequested = recordersRequested
        self.vrcode = vrcode
        self.version = version
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
        self.maxMessages = maxMessages
        self.shiftTime = shiftTime
        self.generateFrames = generateFrames
        self.defaultScenario = defaultScenario
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.messagesSent = messagesSent
        self.bytesSent = bytesSent
        self.lastError = lastError
        self.recorders = recorders
    }

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case targetURL = "targetUrl"
        case recordersRequested
        case vrcode
        case version
        case intervalSeconds
        case durationSeconds
        case maxMessages
        case shiftTime
        case generateFrames
        case defaultScenario
        case createdAt
        case startedAt
        case stoppedAt
        case messagesSent
        case bytesSent
        case lastError
        case recorders
    }
}

public struct RuntimeTestKitRecorder: Codable, Equatable, Sendable {
    public var vrcode: String
    public var baseURL: String
    public var localIP: String?
    public var connected: Bool
    public var joinSent: Bool
    public var joinedAt: Double?
    public var lastReconnectAt: Double?
    public var lastSendDataAt: Double?
    public var messagesSent: Int
    public var bytesSent: Int

    public init(
        vrcode: String,
        baseURL: String,
        localIP: String?,
        connected: Bool,
        joinSent: Bool,
        joinedAt: Double?,
        lastReconnectAt: Double?,
        lastSendDataAt: Double?,
        messagesSent: Int,
        bytesSent: Int
    ) {
        self.vrcode = vrcode
        self.baseURL = baseURL
        self.localIP = localIP
        self.connected = connected
        self.joinSent = joinSent
        self.joinedAt = joinedAt
        self.lastReconnectAt = lastReconnectAt
        self.lastSendDataAt = lastSendDataAt
        self.messagesSent = messagesSent
        self.bytesSent = bytesSent
    }

    enum CodingKeys: String, CodingKey {
        case vrcode
        case baseURL = "baseUrl"
        case localIP = "localIp"
        case connected
        case joinSent
        case joinedAt
        case lastReconnectAt
        case lastSendDataAt
        case messagesSent
        case bytesSent
    }
}
