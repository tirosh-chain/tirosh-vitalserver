import Foundation

public enum RuntimePathState: Codable, Equatable, Sendable {
    case file
    case directory
    case other(String)
    case missing
    case inspectFailed(String)
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "file":
            self = .file
        case "directory":
            self = .directory
        case "missing":
            self = .missing
        default:
            if rawValue.hasPrefix("other: ") {
                self = .other(String(rawValue.dropFirst("other: ".count)))
            } else if rawValue.hasPrefix("inspect-failed: ") {
                self = .inspectFailed(String(rawValue.dropFirst("inspect-failed: ".count)))
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .file:
            return "file"
        case .directory:
            return "directory"
        case .other(let type):
            return "other: \(type)"
        case .missing:
            return "missing"
        case .inspectFailed(let reason):
            return "inspect-failed: \(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var isPresent: Bool {
        switch self {
        case .file, .directory, .other:
            return true
        case .missing, .inspectFailed, .unknown:
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
