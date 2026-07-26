public struct RuntimePackageVersion:
    Codable,
    CustomStringConvertible,
    Equatable,
    Hashable,
    Sendable
{
    public let rawValue: String

    public init?(rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty && component.utf8.allSatisfy { byte in
                      byte >= 48 && byte <= 57
                  }
              })
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let version = RuntimePackageVersion(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "package version must contain only nonempty numeric components separated by dots"
            )
        }
        self = version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
