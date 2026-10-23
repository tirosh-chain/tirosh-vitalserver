import Foundation

/// A contract field whose key is required even when its value is `null`.
///
/// Swift's synthesized `Codable` implementation omits `nil` optional values.
/// Runtime Control contracts use explicit `null` to keep missing and
/// not-reported values distinct, so those fields opt into this wrapper.
@propertyWrapper
public struct RuntimeRequiredNullable<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decodeNil() ? nil : container.decode(Value.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}
