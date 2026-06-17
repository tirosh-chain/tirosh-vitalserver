import Foundation
import Errors

public enum RuntimeTestKitState: String, Codable, Equatable, Sendable {
    case disabled
    case stopped
    case starting
    case running
    case paused
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
    public var beds: [RuntimeTestKitBed]
    public var lastError: String?
    public var readIssues: [RuntimeTestKitReadIssue]

    public init(
        enabled: Bool,
        state: RuntimeTestKitState,
        serviceName: String? = nil,
        apiBaseURL: String? = nil,
        recorderTargetURL: String? = nil,
        startedAt: Date? = nil,
        activeSession: RuntimeTestKitSession? = nil,
        sessions: [RuntimeTestKitSession] = [],
        beds: [RuntimeTestKitBed] = [],
        lastError: String? = nil,
        readIssues: [RuntimeTestKitReadIssue] = []
    ) {
        self.enabled = enabled
        self.state = state
        self.serviceName = serviceName
        self.apiBaseURL = apiBaseURL
        self.recorderTargetURL = recorderTargetURL
        self.startedAt = startedAt
        self.activeSession = activeSession
        self.sessions = sessions
        self.beds = beds
        self.lastError = lastError
        self.readIssues = readIssues
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case state
        case serviceName
        case apiBaseURL
        case recorderTargetURL
        case startedAt
        case activeSession
        case sessions
        case beds
        case lastError
        case readIssues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        state = try container.decode(RuntimeTestKitState.self, forKey: .state)
        serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName)
        apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL)
        recorderTargetURL = try container.decodeIfPresent(String.self, forKey: .recorderTargetURL)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        activeSession = try container.decodeIfPresent(RuntimeTestKitSession.self, forKey: .activeSession)
        sessions = try container.decodeIfPresent([RuntimeTestKitSession].self, forKey: .sessions) ?? []
        beds = try container.decodeIfPresent([RuntimeTestKitBed].self, forKey: .beds) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        readIssues = try container.decodeIfPresent([RuntimeTestKitReadIssue].self, forKey: .readIssues) ?? []
    }
}

public struct RuntimeTestKitReadIssue: Codable, Equatable, Sendable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public struct RuntimeTestKitBed: Codable, Equatable, Sendable, Identifiable {
    public var roomName: String
    public var bedID: String

    public var id: String { roomName }

    public init(roomName: String, bedID: String) {
        self.roomName = roomName
        self.bedID = bedID
    }

    enum CodingKeys: String, CodingKey {
        case roomName
        case bedID = "bedId"
    }
}

public struct RuntimeTestKitCreateBedsRequest: Codable, Equatable, Sendable {
    public var count: Int?
    public var roomNames: [String]
    public var prefix: String
    public var adminUserID: String

    public init(
        count: Int? = nil,
        roomNames: [String] = [],
        prefix: String = "testkit-bed",
        adminUserID: String = "admin"
    ) {
        self.count = count
        self.roomNames = roomNames
        self.prefix = prefix
        self.adminUserID = adminUserID
    }

    enum CodingKeys: String, CodingKey {
        case count
        case roomNames
        case prefix
        case adminUserID = "adminUserId"
    }
}

public struct RuntimeTestKitDeleteBedsRequest: Codable, Equatable, Sendable {
    public var roomNames: [String]

    public init(roomNames: [String]) {
        self.roomNames = roomNames
    }
}

public struct RuntimeTestKitVirtualRecorderStartRequest: Codable, Equatable, Sendable {
    public var scenario: RuntimeTestKitScenario
    public var signalProfile: RuntimeTestKitSignalProfile
    public var recorders: Int
    public var bedRoomNames: [String]
    public var vrcode: String?
    public var version: String
    public var intervalSeconds: Double
    public var durationSeconds: Double?
    public var maxMessages: Int?
    public var shiftTime: Bool
    public var generateFrames: Bool
    public var exportVital: Bool
    public var uploadVital: Bool
    public var vitalUploadEndpoint: String

    public init(
        scenario: RuntimeTestKitScenario = .normal,
        signalProfile: RuntimeTestKitSignalProfile = .normal,
        recorders: Int = 1,
        bedRoomNames: [String] = [],
        vrcode: String? = nil,
        version: String = "testkit",
        intervalSeconds: Double = 1,
        durationSeconds: Double? = nil,
        maxMessages: Int? = nil,
        shiftTime: Bool = true,
        generateFrames: Bool = true,
        exportVital: Bool = false,
        uploadVital: Bool = false,
        vitalUploadEndpoint: String = "/upload"
    ) {
        self.scenario = scenario
        self.signalProfile = signalProfile
        self.recorders = recorders
        self.bedRoomNames = bedRoomNames
        self.vrcode = vrcode
        self.version = version
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
        self.maxMessages = maxMessages
        self.shiftTime = shiftTime
        self.generateFrames = generateFrames
        self.exportVital = exportVital
        self.uploadVital = uploadVital
        self.vitalUploadEndpoint = vitalUploadEndpoint
    }

    enum CodingKeys: String, CodingKey {
        case scenario
        case signalProfile
        case recorders
        case bedRoomNames
        case vrcode
        case version
        case intervalSeconds
        case durationSeconds
        case maxMessages
        case shiftTime
        case generateFrames
        case exportVital
        case uploadVital
        case vitalUploadEndpoint
    }
}

public struct RuntimeTestKitSessionVitalArtifact: Codable, Equatable, Sendable {
    public var path: String
    public var filename: String
    public var sizeBytes: Int
    public var createdAt: Double
    public var format: String
    public var retentionPolicy: String

    public init(
        path: String,
        filename: String,
        sizeBytes: Int,
        createdAt: Double,
        format: String,
        retentionPolicy: String
    ) {
        self.path = path
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.format = format
        self.retentionPolicy = retentionPolicy
    }
}

public struct RuntimeTestKitSessionVitalUploadResult: Codable, Equatable, Sendable {
    public var statusCode: Int
    public var ok: Bool
    public var elapsedSeconds: Double
    public var uploadedAt: Double
    public var responseText: String
    public var error: String?

    public init(
        statusCode: Int,
        ok: Bool,
        elapsedSeconds: Double,
        uploadedAt: Double,
        responseText: String,
        error: String?
    ) {
        self.statusCode = statusCode
        self.ok = ok
        self.elapsedSeconds = elapsedSeconds
        self.uploadedAt = uploadedAt
        self.responseText = responseText
        self.error = error
    }
}

public struct RuntimeTestKitSessionVitalState: Codable, Equatable, Sendable {
    public var exportStatus: String
    public var uploadStatus: String
    public var exportError: String?
    public var uploadError: String?
    public var artifact: RuntimeTestKitSessionVitalArtifact?
    public var uploadResult: RuntimeTestKitSessionVitalUploadResult?

    public init(
        exportStatus: String,
        uploadStatus: String,
        exportError: String? = nil,
        uploadError: String? = nil,
        artifact: RuntimeTestKitSessionVitalArtifact? = nil,
        uploadResult: RuntimeTestKitSessionVitalUploadResult? = nil
    ) {
        self.exportStatus = exportStatus
        self.uploadStatus = uploadStatus
        self.exportError = exportError
        self.uploadError = uploadError
        self.artifact = artifact
        self.uploadResult = uploadResult
    }
}

public struct RuntimeTestKitSession: Codable, Equatable, Sendable {
    public var id: String
    public var state: String
    public var targetURL: String
    public var recordersRequested: Int
    public var bedsRequested: Int
    public var bedRoomNames: [String]
    public var vrcode: String?
    public var version: String
    public var intervalSeconds: Double
    public var durationSeconds: Double?
    public var maxMessages: Int?
    public var shiftTime: Bool
    public var generateFrames: Bool
    public var scenario: String?
    public var defaultScenario: String
    public var createdAt: Double?
    public var startedAt: Double?
    public var stoppedAt: Double?
    public var messagesSent: Int
    public var bytesSent: Int
    public var lastError: String?
    public var cleanupErrors: [RuntimeTestKitCleanupError]
    public var vital: RuntimeTestKitSessionVitalState?
    public var recorders: [RuntimeTestKitRecorder]

    public init(
        id: String,
        state: String,
        targetURL: String,
        recordersRequested: Int,
        bedsRequested: Int = 0,
        bedRoomNames: [String] = [],
        vrcode: String?,
        version: String,
        intervalSeconds: Double,
        durationSeconds: Double?,
        maxMessages: Int?,
        shiftTime: Bool,
        generateFrames: Bool,
        scenario: String? = nil,
        defaultScenario: String,
        createdAt: Double?,
        startedAt: Double?,
        stoppedAt: Double?,
        messagesSent: Int,
        bytesSent: Int,
        lastError: String?,
        cleanupErrors: [RuntimeTestKitCleanupError] = [],
        vital: RuntimeTestKitSessionVitalState? = nil,
        recorders: [RuntimeTestKitRecorder]
    ) {
        self.id = id
        self.state = state
        self.targetURL = targetURL
        self.recordersRequested = recordersRequested
        self.bedsRequested = bedsRequested
        self.bedRoomNames = bedRoomNames
        self.vrcode = vrcode
        self.version = version
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
        self.maxMessages = maxMessages
        self.shiftTime = shiftTime
        self.generateFrames = generateFrames
        self.scenario = scenario
        self.defaultScenario = defaultScenario
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.messagesSent = messagesSent
        self.bytesSent = bytesSent
        self.lastError = lastError
        self.cleanupErrors = cleanupErrors
        self.vital = vital
        self.recorders = recorders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(String.self, forKey: .state)
        targetURL = try container.decode(String.self, forKey: .targetURL)
        recordersRequested = try container.decode(Int.self, forKey: .recordersRequested)
        bedsRequested = try container.decodeIfPresent(Int.self, forKey: .bedsRequested) ?? 0
        bedRoomNames = try container.decodeIfPresent([String].self, forKey: .bedRoomNames) ?? []
        vrcode = try container.decodeIfPresent(String.self, forKey: .vrcode)
        version = try container.decode(String.self, forKey: .version)
        intervalSeconds = try container.decode(Double.self, forKey: .intervalSeconds)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        maxMessages = try container.decodeIfPresent(Int.self, forKey: .maxMessages)
        shiftTime = try container.decode(Bool.self, forKey: .shiftTime)
        generateFrames = try container.decode(Bool.self, forKey: .generateFrames)
        scenario = try container.decodeIfPresent(String.self, forKey: .scenario)
        defaultScenario = try container.decode(String.self, forKey: .defaultScenario)
        createdAt = try container.decodeIfPresent(Double.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt)
        stoppedAt = try container.decodeIfPresent(Double.self, forKey: .stoppedAt)
        messagesSent = try container.decode(Int.self, forKey: .messagesSent)
        bytesSent = try container.decode(Int.self, forKey: .bytesSent)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        cleanupErrors = try container.decodeIfPresent([RuntimeTestKitCleanupError].self, forKey: .cleanupErrors) ?? []
        vital = try container.decodeIfPresent(RuntimeTestKitSessionVitalState.self, forKey: .vital)
        recorders = try container.decode([RuntimeTestKitRecorder].self, forKey: .recorders)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case targetURL = "targetUrl"
        case recordersRequested
        case bedsRequested
        case bedRoomNames
        case vrcode
        case version
        case intervalSeconds
        case durationSeconds
        case maxMessages
        case shiftTime
        case generateFrames
        case scenario
        case defaultScenario
        case createdAt
        case startedAt
        case stoppedAt
        case messagesSent
        case bytesSent
        case lastError
        case cleanupErrors
        case vital
        case recorders
    }
}

public struct RuntimeTestKitCleanupError: Codable, Equatable, Sendable {
    public var vrcode: String
    public var targetURL: String
    public var error: String

    public init(vrcode: String, targetURL: String, error: String) {
        self.vrcode = vrcode
        self.targetURL = targetURL
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case vrcode
        case targetURL = "targetUrl"
        case error
    }
}

public struct RuntimeTestKitRecorderDeletion: Codable, Equatable, Sendable {
    public var vrcode: String
    public var targetURL: String
    public var deleted: Bool
    public var error: String?

    public init(
        vrcode: String,
        targetURL: String,
        deleted: Bool,
        error: String? = nil
    ) {
        self.vrcode = vrcode
        self.targetURL = targetURL
        self.deleted = deleted
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case vrcode
        case targetURL = "targetUrl"
        case deleted
        case error
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
