import Foundation

public enum RuntimeProxyPortReadState: Codable, Equatable, Sendable {
    case loaded(Int)
    case missing(String)
    case empty
    case invalid(String)
    case outOfRange(Int)
    case commandFailed(exitCode: Int32, reason: String)
    case unknown(String)

    public init(rawValue: String) {
        if rawValue.hasPrefix("loaded: port="),
           let port = Int(String(rawValue.dropFirst("loaded: port=".count))) {
            self = .loaded(port)
        } else if rawValue.hasPrefix("missing: reason=") {
            self = .missing(String(rawValue.dropFirst("missing: reason=".count)))
        } else if rawValue == "empty" {
            self = .empty
        } else if rawValue.hasPrefix("invalid: value=") {
            self = .invalid(String(rawValue.dropFirst("invalid: value=".count)))
        } else if rawValue.hasPrefix("out-of-range: value="),
                  let value = Int(String(rawValue.dropFirst("out-of-range: value=".count))) {
            self = .outOfRange(value)
        } else if rawValue.hasPrefix("command-failed: ") {
            self = Self.parseCommandFailure(rawValue) ?? .unknown(rawValue)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .loaded(let port):
            return "loaded: port=\(port)"
        case .missing(let reason):
            return "missing: reason=\(reason)"
        case .empty:
            return "empty"
        case .invalid(let value):
            return "invalid: value=\(value)"
        case .outOfRange(let value):
            return "out-of-range: value=\(value)"
        case .commandFailed(let exitCode, let reason):
            return "command-failed: exit-code=\(exitCode) reason=\(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var port: Int? {
        switch self {
        case .loaded(let port):
            return port
        case .missing, .empty, .invalid, .outOfRange, .commandFailed, .unknown:
            return nil
        }
    }

    public var failureReasons: [RuntimeFailureReason] {
        port == nil ? [.hostProxyConfigInvalid] : []
    }

    public static func observed(_ port: Int) -> RuntimeProxyPortReadState {
        .loaded(port)
    }

    public static func observed(_ port: Int?) -> RuntimeProxyPortReadState {
        port.map(RuntimeProxyPortReadState.loaded)
            ?? .missing("proxy port read state was not provided")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func parseCommandFailure(_ rawValue: String) -> RuntimeProxyPortReadState? {
        let body = String(rawValue.dropFirst("command-failed: ".count))
        let marker = " reason="
        guard body.hasPrefix("exit-code="), let separator = body.range(of: marker) else {
            return nil
        }
        let exitCodeText = body.dropFirst("exit-code=".count)[..<separator.lowerBound]
        guard let exitCode = Int32(exitCodeText) else {
            return nil
        }
        return .commandFailed(exitCode: exitCode, reason: String(body[separator.upperBound...]))
    }
}
