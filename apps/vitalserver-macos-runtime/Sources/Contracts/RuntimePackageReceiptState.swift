import Foundation

public enum RuntimePackageReceiptState: Codable, Equatable, Sendable {
    case present(identifier: String)
    case absent(identifier: String)
    case readFailed(identifier: String, reason: String)
    case forgetFailed(identifier: String, reason: String)
    case unknown(String)

    public init(rawValue: String) {
        if rawValue.hasPrefix("present: identifier=") {
            self = .present(identifier: String(rawValue.dropFirst("present: identifier=".count)))
        } else if rawValue.hasPrefix("absent: identifier=") {
            self = .absent(identifier: String(rawValue.dropFirst("absent: identifier=".count)))
        } else if rawValue.hasPrefix("read-failed: identifier=") {
            self = Self.parseStateWithReason(rawValue, prefix: "read-failed: identifier=")
                .map { .readFailed(identifier: $0.identifier, reason: $0.reason) }
                ?? .unknown(rawValue)
        } else if rawValue.hasPrefix("forget-failed: identifier=") {
            self = Self.parseStateWithReason(rawValue, prefix: "forget-failed: identifier=")
                .map { .forgetFailed(identifier: $0.identifier, reason: $0.reason) }
                ?? .unknown(rawValue)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .present(let identifier):
            return "present: identifier=\(identifier)"
        case .absent(let identifier):
            return "absent: identifier=\(identifier)"
        case .readFailed(let identifier, let reason):
            return "read-failed: identifier=\(identifier) reason=\(reason)"
        case .forgetFailed(let identifier, let reason):
            return "forget-failed: identifier=\(identifier) reason=\(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var blocksUninstallCompletion: Bool {
        switch self {
        case .present, .readFailed, .forgetFailed, .unknown:
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
    ) -> (identifier: String, reason: String)? {
        let body = String(rawValue.dropFirst(prefix.count))
        guard let separator = body.range(of: " reason=") else {
            return nil
        }
        let identifier = String(body[..<separator.lowerBound])
        let reason = String(body[separator.upperBound...])
        guard !identifier.isEmpty else {
            return nil
        }
        return (identifier, reason)
    }
}
