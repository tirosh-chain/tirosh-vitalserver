import Foundation

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

public struct RuntimeStatusDocument: Codable, Equatable, Sendable {
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
    public let containerObservation: RuntimeContainerObservation?

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
        progress: RuntimeProgressDocument? = nil,
        containerObservation: RuntimeContainerObservation? = nil
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
        self.containerObservation = containerObservation
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
        progress: RuntimeProgressDocument? = nil,
        containerObservation: RuntimeContainerObservation? = nil
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
            progress: progress,
            containerObservation: containerObservation
        )
    }
}
