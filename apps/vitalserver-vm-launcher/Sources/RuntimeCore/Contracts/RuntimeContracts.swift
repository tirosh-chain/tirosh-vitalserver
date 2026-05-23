import Foundation

public enum RuntimeOperation: Codable, Equatable, Sendable {
    case install
    case status
    case health
    case watchdog
    case configure
    case verifyBundle
    case stageBundle
    case applyBundle
    case activateGuestUpdate
    case rollback
    case repairDatastore
    case repairProxy
    case startServices
    case stopServices
    case uninstall
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "install":
            self = .install
        case "status":
            self = .status
        case "health":
            self = .health
        case "watchdog":
            self = .watchdog
        case "configure":
            self = .configure
        case "verify-bundle":
            self = .verifyBundle
        case "stage-bundle":
            self = .stageBundle
        case "apply-bundle":
            self = .applyBundle
        case "activate-guest-update", "activate-update":
            self = .activateGuestUpdate
        case "rollback":
            self = .rollback
        case "repair-datastore":
            self = .repairDatastore
        case "repair-proxy":
            self = .repairProxy
        case "start-services":
            self = .startServices
        case "stop-services":
            self = .stopServices
        case "uninstall":
            self = .uninstall
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .install:
            return "install"
        case .status:
            return "status"
        case .health:
            return "health"
        case .watchdog:
            return "watchdog"
        case .configure:
            return "configure"
        case .verifyBundle:
            return "verify-bundle"
        case .stageBundle:
            return "stage-bundle"
        case .applyBundle:
            return "apply-bundle"
        case .activateGuestUpdate:
            return "activate-guest-update"
        case .rollback:
            return "rollback"
        case .repairDatastore:
            return "repair-datastore"
        case .repairProxy:
            return "repair-proxy"
        case .startServices:
            return "start-services"
        case .stopServices:
            return "stop-services"
        case .uninstall:
            return "uninstall"
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

public enum RuntimeProgressPhase: Codable, Equatable, Sendable {
    case preparing
    case waitingForPrivilege
    case running
    case waiting
    case recovering
    case completed
    case failed
    case cancelled
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "preparing":
            self = .preparing
        case "waiting-for-privilege":
            self = .waitingForPrivilege
        case "running":
            self = .running
        case "waiting":
            self = .waiting
        case "recovering":
            self = .recovering
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "cancelled":
            self = .cancelled
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .preparing:
            return "preparing"
        case .waitingForPrivilege:
            return "waiting-for-privilege"
        case .running:
            return "running"
        case .waiting:
            return "waiting"
        case .recovering:
            return "recovering"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
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

public enum RuntimeProgressStepStatus: Codable, Equatable, Sendable {
    case pending
    case started
    case completed
    case failed
    case skipped
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "started":
            self = .started
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "skipped":
            self = .skipped
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .pending:
            return "pending"
        case .started:
            return "started"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
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

public enum GuestActivationStatus: Codable, Equatable {
    case pending
    case running
    case completed
    case failed
    case skipped
    case stale
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "running":
            self = .running
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "skipped":
            self = .skipped
        case "stale":
            self = .stale
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
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        case .stale:
            return "stale"
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

public enum DatastoreRepairStatus: Codable, Equatable {
    case pending
    case running
    case completed
    case failed
    case skipped
    case stale
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "running":
            self = .running
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "skipped":
            self = .skipped
        case "stale":
            self = .stale
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
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        case .stale:
            return "stale"
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

public enum GuestBootstrapStatus: Codable, Equatable {
    case running
    case completed
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "running":
            self = .running
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .running:
            return "running"
        case .completed:
            return "completed"
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

public struct ResourceUsage: Codable, Equatable {
    public let usedBytes: Int64
    public let totalBytes: Int64

    public init(usedBytes: Int64, totalBytes: Int64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public var percent: Double {
        guard totalBytes > 0 else {
            return 0
        }
        return min(max((Double(usedBytes) / Double(totalBytes)) * 100.0, 0), 100)
    }
}

public struct RuntimeProgressDocument: Codable, Equatable {
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let step: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let message: String
    public let reasonCodes: [String]
    public let startedAt: String?
    public let updatedAt: String

    public init(
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        step: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String],
        startedAt: String?,
        updatedAt: String
    ) {
        self.operation = operation
        self.phase = phase
        self.step = step
        self.stepStatus = stepStatus
        self.message = message
        self.reasonCodes = reasonCodes
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public init(
        operation: String,
        phase: String,
        step: String?,
        stepStatus: String?,
        message: String,
        reasonCodes: [String],
        startedAt: String?,
        updatedAt: String
    ) {
        self.init(
            operation: RuntimeOperation(rawValue: operation),
            phase: RuntimeProgressPhase(rawValue: phase),
            step: step.map(RuntimeWorkflowStep.init(rawValue:)),
            stepStatus: stepStatus.map(RuntimeProgressStepStatus.init(rawValue:)),
            message: message,
            reasonCodes: reasonCodes,
            startedAt: startedAt,
            updatedAt: updatedAt
        )
    }
}

public struct GuestUpdateActivationResultDocument: Codable, Equatable {
    public let schemaVersion: Int?
    public let requestId: String?
    public let operation: RuntimeOperation?
    public let status: GuestActivationStatus
    public let message: String?
    public let step: String?
    public let reasonCodes: [String]?
    public let updatedAt: String?

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: RuntimeOperation? = nil,
        status: GuestActivationStatus,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        updatedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.operation = operation
        self.status = status
        self.message = message
        self.step = step
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
    }

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: String? = nil,
        status: String,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        updatedAt: String?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            requestId: requestId,
            operation: operation.map(RuntimeOperation.init(rawValue:)),
            status: GuestActivationStatus(rawValue: status),
            message: message,
            step: step,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt
        )
    }

    public var completed: Bool {
        status == .completed
    }

    public var failed: Bool {
        status == .failed
    }
}

public struct GuestUpdateActivationRequestDocument: Codable, Equatable {
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
        schemaVersion: Int = 2,
        requestId: String,
        requestedAt: String,
        operation: RuntimeOperation = .activateGuestUpdate,
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
        try container.encode("activate-update", forKey: .operation)
        try container.encode(version, forKey: .version)
    }
}

public struct DatastoreRepairResultDocument: Codable, Equatable {
    public let schemaVersion: Int?
    public let requestId: String?
    public let operation: RuntimeOperation?
    public let status: DatastoreRepairStatus
    public let message: String?
    public let step: String?
    public let reasonCodes: [String]?
    public let updatedAt: String?

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: RuntimeOperation? = nil,
        status: DatastoreRepairStatus,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        updatedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.operation = operation
        self.status = status
        self.message = message
        self.step = step
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
    }

    public init(
        schemaVersion: Int? = nil,
        requestId: String? = nil,
        operation: String? = nil,
        status: String,
        message: String?,
        step: String? = nil,
        reasonCodes: [String]? = nil,
        updatedAt: String?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            requestId: requestId,
            operation: operation.map(RuntimeOperation.init(rawValue:)),
            status: DatastoreRepairStatus(rawValue: status),
            message: message,
            step: step,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt
        )
    }

    public var completed: Bool {
        status == .completed
    }

    public var failed: Bool {
        status == .failed
    }
}

public struct GuestBootstrapResultDocument: Codable, Equatable {
    public let schemaVersion: Int?
    public let operation: RuntimeOperation?
    public let status: GuestBootstrapStatus
    public let message: String?
    public let reasonCodes: [RuntimeFailureReason]?
    public let updatedAt: String?

    public init(
        schemaVersion: Int? = nil,
        operation: RuntimeOperation? = nil,
        status: GuestBootstrapStatus,
        message: String?,
        reasonCodes: [RuntimeFailureReason]? = nil,
        updatedAt: String?
    ) {
        self.schemaVersion = schemaVersion
        self.operation = operation
        self.status = status
        self.message = message
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
    }

    public init(
        schemaVersion: Int? = nil,
        operation: String? = nil,
        status: String,
        message: String?,
        reasonCodes: [RuntimeFailureReason]? = nil,
        updatedAt: String?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            operation: operation.map(RuntimeOperation.init(rawValue:)),
            status: GuestBootstrapStatus(rawValue: status),
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt
        )
    }
}

public enum RuntimeFailureReason: Codable, Equatable {
    case missingVMBin
    case missingProxyRunner
    case missingRootfsBase
    case missingVMDisk
    case vmService(String)
    case proxyService(String)
    case watchdogService(String)
    case hostProxyHTTP(String)
    case redisUIHTTP(String)
    case swaggerUIHTTP(String)
    case guestHTTP(String)
    case proxyPortInUse(port: Int, listeners: String)
    case guestBootstrapMissingRuntimePackages
    case guestBootstrapFailed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "missing-vm-bin":
            self = .missingVMBin
        case "missing-proxy-runner":
            self = .missingProxyRunner
        case "missing-rootfs-base":
            self = .missingRootfsBase
        case "missing-vm-disk":
            self = .missingVMDisk
        case "guest-bootstrap-missing-runtime-packages":
            self = .guestBootstrapMissingRuntimePackages
        case "guest-bootstrap-failed":
            self = .guestBootstrapFailed
        default:
            if rawValue.hasPrefix("vm-service-") {
                self = .vmService(String(rawValue.dropFirst("vm-service-".count)))
            } else if rawValue.hasPrefix("proxy-service-") {
                self = .proxyService(String(rawValue.dropFirst("proxy-service-".count)))
            } else if rawValue.hasPrefix("watchdog-service-") {
                self = .watchdogService(String(rawValue.dropFirst("watchdog-service-".count)))
            } else if rawValue.hasPrefix("host-proxy-http-") {
                self = .hostProxyHTTP(String(rawValue.dropFirst("host-proxy-http-".count)))
            } else if rawValue.hasPrefix("redis-ui-http-") {
                self = .redisUIHTTP(String(rawValue.dropFirst("redis-ui-http-".count)))
            } else if rawValue.hasPrefix("swagger-ui-http-") {
                self = .swaggerUIHTTP(String(rawValue.dropFirst("swagger-ui-http-".count)))
            } else if rawValue.hasPrefix("guest-http-") {
                self = .guestHTTP(String(rawValue.dropFirst("guest-http-".count)))
            } else if let parsed = RuntimeFailureReason.parseProxyPortInUse(rawValue) {
                self = parsed
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .missingVMBin:
            return "missing-vm-bin"
        case .missingProxyRunner:
            return "missing-proxy-runner"
        case .missingRootfsBase:
            return "missing-rootfs-base"
        case .missingVMDisk:
            return "missing-vm-disk"
        case .vmService(let state):
            return "vm-service-\(state)"
        case .proxyService(let state):
            return "proxy-service-\(state)"
        case .watchdogService(let state):
            return "watchdog-service-\(state)"
        case .hostProxyHTTP(let status):
            return "host-proxy-http-\(status)"
        case .redisUIHTTP(let status):
            return "redis-ui-http-\(status)"
        case .swaggerUIHTTP(let status):
            return "swagger-ui-http-\(status)"
        case .guestHTTP(let status):
            return "guest-http-\(status)"
        case .proxyPortInUse(let port, let listeners):
            return "proxy-port-\(port)-in-use-by-\(listeners)"
        case .guestBootstrapMissingRuntimePackages:
            return "guest-bootstrap-missing-runtime-packages"
        case .guestBootstrapFailed:
            return "guest-bootstrap-failed"
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

    private static func parseProxyPortInUse(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "proxy-port-"
        let marker = "-in-use-by-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let portText = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        guard let port = Int(portText) else {
            return nil
        }
        return .proxyPortInUse(port: port, listeners: String(rawValue[markerRange.upperBound...]))
    }
}

public struct RuntimeHealthSnapshot: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmIP: String?
    public let proxyPort: Int
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let failureReasons: [RuntimeFailureReason]

    public init(
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        failureReasons: [RuntimeFailureReason]
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.failureReasons = failureReasons
    }

    public var isHealthy: Bool {
        failureReasons.isEmpty
    }
}

public struct GuestRuntimeStateDocument: Codable, Equatable {
    public let vmIP: String?
    public let updatedAt: String?
    public let bootID: String?
    public let guestHTTP: String?
    public let redisUIHTTP: String?
    public let swaggerUIHTTP: String?
    public let cpuUsagePercent: Double?
    public let memory: ResourceUsage?
    public let systemDisk: ResourceUsage?

    public init(
        vmIP: String?,
        updatedAt: String? = nil,
        bootID: String? = nil,
        guestHTTP: String?,
        redisUIHTTP: String?,
        swaggerUIHTTP: String?,
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        systemDisk: ResourceUsage? = nil
    ) {
        self.vmIP = vmIP
        self.updatedAt = updatedAt
        self.bootID = bootID
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.systemDisk = systemDisk
    }

}

public enum RuntimeStatusLevel: Codable, Equatable, Sendable {
    case installing
    case updating
    case recovering
    case healthy
    case degraded
    case critical
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "installing":
            self = .installing
        case "updating":
            self = .updating
        case "recovering":
            self = .recovering
        case "healthy":
            self = .healthy
        case "degraded":
            self = .degraded
        case "critical":
            self = .critical
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .installing:
            return "installing"
        case .updating:
            return "updating"
        case .recovering:
            return "recovering"
        case .healthy:
            return "healthy"
        case .degraded:
            return "degraded"
        case .critical:
            return "critical"
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

public struct RuntimeStatusDocument: Codable, Equatable {
    public let schemaVersion: Int?
    public let product: String
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let message: String
    public let updatedAt: String
    public let productRoot: String
    public let runtimeHome: String
    public let runtimeVersion: String
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmIP: String?
    public let proxyPort: Int
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let redisUIHTTP: String?
    public let swaggerUIHTTP: String?
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let failureReasons: [RuntimeFailureReason]
    public let latestBackup: String?
    public let progress: RuntimeProgressDocument?

    public init(
        schemaVersion: Int? = nil,
        product: String,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        updatedAt: String,
        productRoot: String,
        runtimeHome: String,
        runtimeVersion: String,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String?,
        swaggerUIHTTP: String?,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        failureReasons: [RuntimeFailureReason],
        latestBackup: String?,
        progress: RuntimeProgressDocument? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.status = status
        self.operation = operation
        self.message = message
        self.updatedAt = updatedAt
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.runtimeVersion = runtimeVersion
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.failureReasons = failureReasons
        self.latestBackup = latestBackup
        self.progress = progress
    }

    public init(
        schemaVersion: Int? = nil,
        product: String,
        status: RuntimeStatusLevel,
        operation: String,
        message: String,
        updatedAt: String,
        productRoot: String,
        runtimeHome: String,
        runtimeVersion: String,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String?,
        swaggerUIHTTP: String?,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        failureReasons: [RuntimeFailureReason],
        latestBackup: String?,
        progress: RuntimeProgressDocument? = nil
    ) {
        self.init(
            schemaVersion: schemaVersion,
            product: product,
            status: status,
            operation: RuntimeOperation(rawValue: operation),
            message: message,
            updatedAt: updatedAt,
            productRoot: productRoot,
            runtimeHome: runtimeHome,
            runtimeVersion: runtimeVersion,
            vmService: vmService,
            proxyService: proxyService,
            watchdogService: watchdogService,
            vmIP: vmIP,
            proxyPort: proxyPort,
            hostProxyHTTP: hostProxyHTTP,
            guestHTTP: guestHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            failureReasons: failureReasons,
            latestBackup: latestBackup,
            progress: progress
        )
    }
}
