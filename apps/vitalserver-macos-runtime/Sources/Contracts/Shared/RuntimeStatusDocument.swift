import Foundation

public enum RuntimeStatusLevel: Codable, Equatable, Sendable {
    case installing
    case initializing
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
        case "initializing":
            self = .initializing
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
        case .initializing:
            return "initializing"
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
    public let productRoot: String
    public let runtimeHome: String
    public let runtimeVersion: String
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let guestAddressRead: RuntimeGuestAddressReadResult?
    public let vmIP: String?
    public let proxyPort: Int?
    public let proxyPortReadState: RuntimeProxyPortReadState?
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let redisUIHTTP: String?
    public let swaggerUIHTTP: String?
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let latestBackup: String?

    public init(
        schemaVersion: Int? = nil,
        product: String,
        status: RuntimeStatusLevel,
        productRoot: String,
        runtimeHome: String,
        runtimeVersion: String,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        guestAddressRead: RuntimeGuestAddressReadResult? = nil,
        vmIP: String?,
        proxyPort: Int?,
        proxyPortReadState: RuntimeProxyPortReadState? = nil,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String?,
        swaggerUIHTTP: String?,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        latestBackup: String?
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.status = status
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.runtimeVersion = runtimeVersion
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.guestAddressRead = guestAddressRead
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.proxyPortReadState = proxyPortReadState
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.latestBackup = latestBackup
    }
}
