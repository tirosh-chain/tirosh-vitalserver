import Foundation

public enum RuntimeInstallArtifactState: Codable, Equatable, Sendable {
    case present(path: String)
    case absent(path: String)
    case inspectFailed(path: String, reason: String)
    case unknown(String)

    public init(rawValue: String) {
        if rawValue.hasPrefix("present: path=") {
            self = .present(path: String(rawValue.dropFirst("present: path=".count)))
        } else if rawValue.hasPrefix("absent: path=") {
            self = .absent(path: String(rawValue.dropFirst("absent: path=".count)))
        } else if rawValue.hasPrefix("inspect-failed: path=") {
            self = Self.parseStateWithReason(rawValue, prefix: "inspect-failed: path=")
                .map { .inspectFailed(path: $0.path, reason: $0.reason) }
                ?? .unknown(rawValue)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .present(let path):
            return "present: path=\(path)"
        case .absent(let path):
            return "absent: path=\(path)"
        case .inspectFailed(let path, let reason):
            return "inspect-failed: path=\(path) reason=\(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var blocksFreshInstall: Bool {
        switch self {
        case .present, .inspectFailed, .unknown:
            return true
        case .absent:
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
