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
    case auditProxyHTTP(String)
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
            } else if rawValue.hasPrefix("audit-proxy-http-") {
                self = .auditProxyHTTP(String(rawValue.dropFirst("audit-proxy-http-".count)))
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
        case .auditProxyHTTP(let status):
            return "audit-proxy-http-\(status)"
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
