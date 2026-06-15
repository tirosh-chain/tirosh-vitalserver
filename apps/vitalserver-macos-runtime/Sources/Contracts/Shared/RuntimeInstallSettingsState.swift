import Foundation

public enum RuntimeInstallSettingsState: Codable, Equatable, Sendable {
    case missing(path: String)
    case proxyPortMissing(path: String)
    case defaulted(path: String, proxyPort: Int)
    case loaded(path: String, proxyPort: Int)
    case readFailed(path: String, reason: String)
    case invalid(path: String, reason: String)
    case unknown(String)

    public init(rawValue: String) {
        if rawValue.hasPrefix("missing: path=") {
            self = Self.parseStateWithPath(rawValue, prefix: "missing: path=")
                .map { .missing(path: $0) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("proxy-port-missing: path=") {
            self = Self.parseStateWithPath(rawValue, prefix: "proxy-port-missing: path=")
                .map { .proxyPortMissing(path: $0) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("defaulted: path=") {
            self = Self.parseStateWithProxyPort(rawValue, prefix: "defaulted: path=")
                .map { .defaulted(path: $0.path, proxyPort: $0.proxyPort) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("loaded: path=") {
            self = Self.parseStateWithProxyPort(rawValue, prefix: "loaded: path=")
                .map { .loaded(path: $0.path, proxyPort: $0.proxyPort) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("read-failed: path=") {
            self = Self.parseStateWithReason(rawValue, prefix: "read-failed: path=")
                .map { .readFailed(path: $0.path, reason: $0.reason) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("invalid: path=") {
            self = Self.parseStateWithReason(rawValue, prefix: "invalid: path=")
                .map { .invalid(path: $0.path, reason: $0.reason) }
                ?? .unknown(rawValue)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .missing(let path):
            return "missing: path=\(path)"
        case .proxyPortMissing(let path):
            return "proxy-port-missing: path=\(path)"
        case .defaulted(let path, let proxyPort):
            return "defaulted: path=\(path) proxy-port=\(proxyPort)"
        case .loaded(let path, let proxyPort):
            return "loaded: path=\(path) proxy-port=\(proxyPort)"
        case .readFailed(let path, let reason):
            return "read-failed: path=\(path) reason=\(reason)"
        case .invalid(let path, let reason):
            return "invalid: path=\(path) reason=\(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var proxyPort: Int? {
        switch self {
        case .defaulted(_, let proxyPort), .loaded(_, let proxyPort):
            return proxyPort
        case .missing, .proxyPortMissing, .readFailed, .invalid, .unknown:
            return nil
        }
    }

    public var blocksFreshInstall: Bool {
        switch self {
        case .missing, .proxyPortMissing, .readFailed, .invalid, .unknown:
            return true
        case .defaulted, .loaded:
            return false
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

    private static func parseStateWithProxyPort(
        _ rawValue: String,
        prefix: String
    ) -> (path: String, proxyPort: Int)? {
        let body = String(rawValue.dropFirst(prefix.count))
        guard let separator = body.range(of: " proxy-port=") else {
            return nil
        }
        let path = String(body[..<separator.lowerBound])
        let proxyPortText = String(body[separator.upperBound...])
        guard !path.isEmpty, let proxyPort = Int(proxyPortText) else {
            return nil
        }
        return (path, proxyPort)
    }

    private static func parseStateWithPath(
        _ rawValue: String,
        prefix: String
    ) -> String? {
        let path = String(rawValue.dropFirst(prefix.count))
        guard !path.isEmpty else {
            return nil
        }
        return path
    }

    private static func parseStateWithReason(
        _ rawValue: String,
        prefix: String
    ) -> (path: String, reason: String)? {
        let body = String(rawValue.dropFirst(prefix.count))
        guard let separator = body.range(of: " reason=") else {
            return nil
        }
        let path = String(body[..<separator.lowerBound])
        let reason = String(body[separator.upperBound...])
        guard !path.isEmpty else {
            return nil
        }
        return (path, reason)
    }
}

public struct RuntimeFreshInstallServiceState: Codable, Equatable, Sendable {
    public let label: String
    public let state: RuntimeServiceState

    public init(label: String, state: RuntimeServiceState) {
        self.label = label
        self.state = state
    }
}

public struct RuntimeFreshInstallPreflightDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let passed: Bool
    public let proxyPort: Int?
    public let blockers: [String]
    public let settingsState: RuntimeInstallSettingsState
    public let artifactStates: [RuntimeInstallArtifactState]
    public let serviceStates: [RuntimeFreshInstallServiceState]
    public let packageReceiptStates: [RuntimePackageReceiptState]
    public let proxyPortState: RuntimeHostProxyPortState?

    public init(
        schemaVersion: Int = 1,
        passed: Bool,
        proxyPort: Int?,
        blockers: [String],
        settingsState: RuntimeInstallSettingsState,
        artifactStates: [RuntimeInstallArtifactState],
        serviceStates: [RuntimeFreshInstallServiceState],
        packageReceiptStates: [RuntimePackageReceiptState],
        proxyPortState: RuntimeHostProxyPortState?
    ) {
        self.schemaVersion = schemaVersion
        self.passed = passed
        self.proxyPort = proxyPort
        self.blockers = blockers
        self.settingsState = settingsState
        self.artifactStates = artifactStates
        self.serviceStates = serviceStates
        self.packageReceiptStates = packageReceiptStates
        self.proxyPortState = proxyPortState
    }
}
