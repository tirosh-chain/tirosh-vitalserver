public enum RuntimeVMState: Codable, Equatable, Sendable {
    case notInstalled
    case stopped
    case starting
    case running
    case stale
    case unreachable
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "not-installed":
            self = .notInstalled
        case "stopped":
            self = .stopped
        case "starting":
            self = .starting
        case "running":
            self = .running
        case "stale":
            self = .stale
        case "unreachable":
            self = .unreachable
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .notInstalled:
            "not-installed"
        case .stopped:
            "stopped"
        case .starting:
            "starting"
        case .running:
            "running"
        case .stale:
            "stale"
        case .unreachable:
            "unreachable"
        case .failed:
            "failed"
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
