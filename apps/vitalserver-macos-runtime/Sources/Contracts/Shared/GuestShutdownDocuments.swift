import Foundation

public enum GuestShutdownStatus: Codable, Equatable, Sendable {
    case pending
    case running
    case ready
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "running":
            self = .running
        case "ready":
            self = .ready
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .pending:
            return "pending"
        case .running:
            return "running"
        case .ready:
            return "ready"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum GuestShutdownPhase: Codable, Equatable, Sendable {
    case preparing
    case prepared
    case poweroffReady
    case poweroffRequested
    case poweroffFailed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "preparing":
            self = .preparing
        case "prepared":
            self = .prepared
        case "poweroff-ready":
            self = .poweroffReady
        case "poweroff-requested":
            self = .poweroffRequested
        case "poweroff-failed":
            self = .poweroffFailed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .preparing:
            return "preparing"
        case .prepared:
            return "prepared"
        case .poweroffReady:
            return "poweroff-ready"
        case .poweroffRequested:
            return "poweroff-requested"
        case .poweroffFailed:
            return "poweroff-failed"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct GuestUpdateShutdownResultDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int?
    public let requestId: String?
    public let operation: RuntimeOperation?
    public let status: GuestShutdownStatus
    public let shutdownPhase: GuestShutdownPhase?
    public let message: String?
    public let step: String?
    public let reasonCodes: [String]?
    public let redisBackupPath: String?
    public let details: GuestUpdateShutdownFailureDetails?
    public let updatedAt: String?

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: RuntimeOperation? = nil,
        status: GuestShutdownStatus,
        shutdownPhase: GuestShutdownPhase? = nil,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        redisBackupPath: String? = nil,
        details: GuestUpdateShutdownFailureDetails? = nil,
        updatedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.operation = operation
        self.status = status
        self.shutdownPhase = shutdownPhase
        self.message = message
        self.step = step
        self.reasonCodes = reasonCodes
        self.redisBackupPath = redisBackupPath
        self.details = details
        self.updatedAt = updatedAt
    }
}

public struct GuestUpdateShutdownFailureDetails: Codable, Equatable, Sendable {
    public let stopAction: String?
    public let failedService: String?
    public let stopTimeoutSeconds: Double?
    public let commandTimeoutSeconds: Double?
    public let remainingServices: [String]?
    public let availableServices: [String]?
    public let serviceStates: [GuestUpdateShutdownServiceState]?
    public let failureSnapshotPath: String?

    public init(
        stopAction: String? = nil,
        failedService: String? = nil,
        stopTimeoutSeconds: Double? = nil,
        commandTimeoutSeconds: Double? = nil,
        remainingServices: [String]? = nil,
        availableServices: [String]? = nil,
        serviceStates: [GuestUpdateShutdownServiceState]? = nil,
        failureSnapshotPath: String? = nil
    ) {
        self.stopAction = stopAction
        self.failedService = failedService
        self.stopTimeoutSeconds = stopTimeoutSeconds
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.remainingServices = remainingServices
        self.availableServices = availableServices
        self.serviceStates = serviceStates
        self.failureSnapshotPath = failureSnapshotPath
    }
}

public struct GuestUpdateShutdownServiceState: Codable, Equatable, Sendable {
    public let service: String
    public let container: String
    public let state: String
    public let exitCode: Int?
    public let health: String?

    public init(
        service: String,
        container: String,
        state: String,
        exitCode: Int? = nil,
        health: String? = nil
    ) {
        self.service = service
        self.container = container
        self.state = state
        self.exitCode = exitCode
        self.health = health
    }
}

public struct GuestUpdateShutdownRequestDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestId: String
    public let requestedAt: String
    public let operation: RuntimeOperation
    public let version: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestId
        case requestedAt
        case operation
        case version
    }

    public init(
        schemaVersion: Int = 1,
        requestId: String,
        requestedAt: String,
        operation: RuntimeOperation = .prepareUpdateShutdown,
        version: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.requestedAt = requestedAt
        self.operation = operation
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            requestId: try container.decode(String.self, forKey: .requestId),
            requestedAt: try container.decode(String.self, forKey: .requestedAt),
            operation: try container.decode(RuntimeOperation.self, forKey: .operation),
            version: try container.decode(String.self, forKey: .version)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encode("prepare-update-shutdown", forKey: .operation)
        try container.encode(version, forKey: .version)
    }
}
