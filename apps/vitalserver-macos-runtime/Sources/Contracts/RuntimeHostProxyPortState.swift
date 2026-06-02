import Foundation

public enum RuntimeHostProxyPortState: Codable, Equatable, Sendable {
    case clear(port: Int)
    case occupied(port: Int, listeners: String)
    case inspectFailed(port: Int, reason: String)
    case unknown(String)

    public init(rawValue: String) {
        if rawValue.hasPrefix("clear: port="),
           let port = Int(String(rawValue.dropFirst("clear: port=".count))) {
            self = .clear(port: port)
        } else if rawValue.hasPrefix("occupied: ") {
            self = Self.parsePortWithValue(rawValue, prefix: "occupied: ", key: "listeners")
                .map { .occupied(port: $0.port, listeners: $0.value) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("inspect-failed: ") {
            self = Self.parsePortWithValue(rawValue, prefix: "inspect-failed: ", key: "reason")
                .map { .inspectFailed(port: $0.port, reason: $0.value) }
                ?? .unknown(rawValue)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .clear(let port):
            return "clear: port=\(port)"
        case .occupied(let port, let listeners):
            return "occupied: port=\(port) listeners=\(listeners)"
        case .inspectFailed(let port, let reason):
            return "inspect-failed: port=\(port) reason=\(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var blocksFreshInstall: Bool {
        switch self {
        case .occupied, .inspectFailed, .unknown:
            return true
        case .clear:
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

    private static func parsePortWithValue(
        _ rawValue: String,
        prefix: String,
        key: String
    ) -> (port: Int, value: String)? {
        let body = String(rawValue.dropFirst(prefix.count))
        let valueMarker = " \(key)="
        guard body.hasPrefix("port="), let separator = body.range(of: valueMarker) else {
            return nil
        }
        let portText = body.dropFirst("port=".count)[..<separator.lowerBound]
        guard let port = Int(portText) else {
            return nil
        }
        return (port, String(body[separator.upperBound...]))
    }
}
