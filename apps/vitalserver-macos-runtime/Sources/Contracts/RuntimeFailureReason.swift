import Foundation

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
        case .runtimeStateStale:
            self = .guestRuntimeStateStale
        case .diskAttachmentInvalid, .guestFilesystemError, .guestFilesystemReadOnly, .guestDiskIO:
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
