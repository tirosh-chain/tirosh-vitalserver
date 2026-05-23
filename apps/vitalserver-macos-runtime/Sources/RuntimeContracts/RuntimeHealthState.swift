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
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "loaded":
            self = .loaded
        case "not loaded", "not-loaded":
            self = .notLoaded
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .loaded:
            "loaded"
        case .notLoaded:
            "not loaded"
        case .unknown(let value):
            value
        }
    }

    public var isLoaded: Bool {
        self == .loaded
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
