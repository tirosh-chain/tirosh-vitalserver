public enum RuntimeFileState: Codable, Equatable, Sendable {
    case executable
    case present
    case missing
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "executable":
            self = .executable
        case "present":
            self = .present
        case "missing":
            self = .missing
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .executable:
            "executable"
        case .present:
            "present"
        case .missing:
            "missing"
        case .unknown(let value):
            value
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

public enum RuntimeServiceState: Codable, Equatable, Sendable {
    case loaded
    case notLoaded
    case readFailed(String)
    case permissionDenied(String)
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "loaded":
            self = .loaded
        case "not loaded", "not-loaded":
            self = .notLoaded
        case "read failed", "read-failed":
            self = .readFailed("")
        case "permission denied", "permission-denied":
            self = .permissionDenied("")
        default:
            if rawValue.hasPrefix("read failed: ") {
                self = .readFailed(String(rawValue.dropFirst("read failed: ".count)))
            } else if rawValue.hasPrefix("permission denied: ") {
                self = .permissionDenied(String(rawValue.dropFirst("permission denied: ".count)))
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .loaded:
            "loaded"
        case .notLoaded:
            "not loaded"
        case .readFailed(let reason):
            reason.isEmpty ? "read failed" : "read failed: \(reason)"
        case .permissionDenied(let reason):
            reason.isEmpty ? "permission denied" : "permission denied: \(reason)"
        case .unknown(let value):
            value
        }
    }

    public var isLoaded: Bool {
        self == .loaded
    }

    public var isReadFailure: Bool {
        switch self {
        case .readFailed, .permissionDenied, .unknown:
            return true
        case .loaded, .notLoaded:
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
}
