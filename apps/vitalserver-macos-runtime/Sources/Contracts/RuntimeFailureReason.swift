import Foundation

public enum RuntimeDomainErrorCategory: String, Codable, Equatable, Sendable {
    case installation
    case vmLifecycle
    case hostProxy
    case hostService
    case guestNetworking
    case guestAgent
    case guestBootstrap
    case guestStorage
    case container
    case vitalDB
    case auxiliaryUI
    case hostResources
    case configuration
    case observability
    case unknown
}

public enum RuntimeDomainErrorSeverity: String, Codable, Equatable, Sendable {
    case warning
    case critical
}

public enum RuntimeDomainRecoveryAction: String, Codable, Equatable, Sendable {
    case installRuntime
    case restartVMService
    case restartProxyService
    case restartWatchdogService
    case waitForGuest
    case restartGuestAgent
    case repairGuestBootstrap
    case restartContainerServices
    case repairProxyConfiguration
    case freeProxyPort
    case inspectVitalDBObservation
    case backupAndRecreateVM
    case fixConfiguration
    case freeHostResources
    case inspectLogs
}

public struct RuntimeDomainError: Codable, Equatable, Sendable {
    public let code: RuntimeFailureReason
    public let category: RuntimeDomainErrorCategory
    public let severity: RuntimeDomainErrorSeverity
    public let recoveryAction: RuntimeDomainRecoveryAction

    public init(_ code: RuntimeFailureReason) {
        self.code = code
        self.category = code.domainCategory
        self.severity = code.domainSeverity
        self.recoveryAction = code.recoveryAction
    }
}

public enum RuntimeFailureReason: Codable, Equatable, Sendable {
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
    case guestRuntimeStateStale
    case auditProxyHTTP(String)
    case containerService(service: String, state: String)
    case vitalDBAnomaly(kind: String, subject: String)
    case proxyPortInUse(port: Int, listeners: String)
    case guestBootstrapMissingRuntimePackages
    case guestBootstrapFailed
    case unknown(String)

    public init(vmError: RuntimeVMError) {
        switch vmError {
        case .missingExecutable:
            self = .missingVMBin
        case .missingRootfsBase:
            self = .missingRootfsBase
        case .missingDisk:
            self = .missingVMDisk
        case .serviceNotLoaded(let state):
            self = .vmService(state)
        case .missingIPAddress:
            self = .guestHTTP("missing-vm-ip")
        case .runtimeStateMissing:
            self = .unknown(vmError.rawValue)
        case .runtimeStateStale:
            self = .guestRuntimeStateStale
        case .launchFailed, .invalidConfiguration, .hostResourceUnavailable,
             .diskAttachmentInvalid, .guestFilesystemError, .guestFilesystemReadOnly, .guestDiskIO:
            self = .unknown(vmError.rawValue)
        case .guestHTTP(let status):
            self = .guestHTTP(status)
        case .guestBootstrapMissingRuntimePackages:
            self = .guestBootstrapMissingRuntimePackages
        case .guestBootstrapFailed:
            self = .guestBootstrapFailed
        case .unknown(let value):
            self = .unknown(value)
        }
    }

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
        case "guest-runtime-state-stale":
            self = .guestRuntimeStateStale
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
            } else if rawValue.hasPrefix("audit-proxy-http-") {
                self = .auditProxyHTTP(String(rawValue.dropFirst("audit-proxy-http-".count)))
            } else if let parsed = RuntimeFailureReason.parseContainerService(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseVitalDBAnomaly(rawValue) {
                self = parsed
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
        case .guestRuntimeStateStale:
            return "guest-runtime-state-stale"
        case .auditProxyHTTP(let status):
            return "audit-proxy-http-\(status)"
        case .containerService(let service, let state):
            return "container-service-\(service)-state-\(state)"
        case .vitalDBAnomaly(let kind, let subject):
            return "vitaldb-anomaly-\(kind)-subject-\(subject)"
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

    private static func parseContainerService(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "container-service-"
        let marker = "-state-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let service = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        return .containerService(service: String(service), state: String(rawValue[markerRange.upperBound...]))
    }

    private static func parseVitalDBAnomaly(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "vitaldb-anomaly-"
        let marker = "-subject-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let kind = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        return .vitalDBAnomaly(kind: String(kind), subject: String(rawValue[markerRange.upperBound...]))
    }
}

public extension RuntimeFailureReason {
    var domainError: RuntimeDomainError {
        RuntimeDomainError(self)
    }

    var domainCategory: RuntimeDomainErrorCategory {
        if let vmError {
            return RuntimeDomainErrorCategory(vmError.category)
        }
        switch self {
        case .missingVMBin, .missingProxyRunner, .missingRootfsBase, .missingVMDisk:
            return .installation
        case .vmService:
            return .vmLifecycle
        case .proxyService, .hostProxyHTTP, .proxyPortInUse:
            return .hostProxy
        case .watchdogService:
            return .observability
        case .redisUIHTTP, .swaggerUIHTTP:
            return .auxiliaryUI
        case .guestHTTP:
            return .guestNetworking
        case .guestRuntimeStateStale:
            return .guestAgent
        case .guestBootstrapMissingRuntimePackages, .guestBootstrapFailed:
            return .guestBootstrap
        case .auditProxyHTTP, .containerService:
            return .container
        case .vitalDBAnomaly:
            return .vitalDB
        case .unknown:
            return .unknown
        }
    }

    var domainSeverity: RuntimeDomainErrorSeverity {
        switch self {
        case .redisUIHTTP, .swaggerUIHTTP, .watchdogService, .guestRuntimeStateStale:
            return .warning
        case .unknown(let value):
            return value.hasPrefix("vm-") ? .critical : .warning
        default:
            return .critical
        }
    }

    var recoveryAction: RuntimeDomainRecoveryAction {
        if let vmError {
            return RuntimeDomainRecoveryAction(vmError.recoveryAction)
        }
        switch self {
        case .missingVMBin, .missingProxyRunner, .missingRootfsBase, .missingVMDisk:
            return .installRuntime
        case .vmService:
            return .restartVMService
        case .proxyService, .hostProxyHTTP:
            return .restartProxyService
        case .watchdogService:
            return .restartWatchdogService
        case .redisUIHTTP, .swaggerUIHTTP:
            return .inspectLogs
        case .guestHTTP:
            return .waitForGuest
        case .guestRuntimeStateStale:
            return .restartGuestAgent
        case .auditProxyHTTP, .containerService:
            return .restartContainerServices
        case .vitalDBAnomaly:
            return .inspectVitalDBObservation
        case .proxyPortInUse:
            return .freeProxyPort
        case .guestBootstrapMissingRuntimePackages, .guestBootstrapFailed:
            return .repairGuestBootstrap
        case .unknown:
            return .inspectLogs
        }
    }

    var requiresDataPreservationBeforeRecovery: Bool {
        recoveryAction == .backupAndRecreateVM
    }

    private var vmError: RuntimeVMError? {
        let parsed = RuntimeVMError(rawValue: rawValue)
        if case .unknown(let value) = parsed {
            return value.hasPrefix("vm-") ? parsed : nil
        }
        return parsed
    }
}

private extension RuntimeDomainErrorCategory {
    init(_ category: RuntimeVMErrorCategory) {
        switch category {
        case .installation:
            self = .installation
        case .lifecycle:
            self = .vmLifecycle
        case .networking:
            self = .guestNetworking
        case .guestAgent:
            self = .guestAgent
        case .guestBootstrap:
            self = .guestBootstrap
        case .guestStorage:
            self = .guestStorage
        case .configuration:
            self = .configuration
        case .hostResources:
            self = .hostResources
        case .unknown:
            self = .unknown
        }
    }
}

private extension RuntimeDomainRecoveryAction {
    init(_ action: RuntimeVMRecoveryAction) {
        switch action {
        case .installRuntime:
            self = .installRuntime
        case .restartVMService:
            self = .restartVMService
        case .waitForGuest:
            self = .waitForGuest
        case .restartGuestAgent:
            self = .restartGuestAgent
        case .repairGuestBootstrap:
            self = .repairGuestBootstrap
        case .backupAndRecreateVM:
            self = .backupAndRecreateVM
        case .fixConfiguration:
            self = .fixConfiguration
        case .freeHostResources:
            self = .freeHostResources
        case .inspectLogs:
            self = .inspectLogs
        }
    }
}
