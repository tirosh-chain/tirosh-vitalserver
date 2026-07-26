public enum RuntimeGuestAddressSource: String, Codable, Equatable, Sendable {
    case platformAgent = "platform-agent"
}

public enum RuntimeGuestAddressReadState: String, Codable, Equatable, Sendable {
    case notReported
    case loaded
    case missing
    case invalid
    case stale
    case readFailed
}

public struct RuntimeGuestAddressReadResult: Codable, Equatable, Sendable {
    public let state: RuntimeGuestAddressReadState
    public let address: String?
    public let source: RuntimeGuestAddressSource?
    public let reason: String?

    public init(
        state: RuntimeGuestAddressReadState,
        address: String? = nil,
        source: RuntimeGuestAddressSource? = nil,
        reason: String? = nil
    ) {
        self.state = state
        self.address = address
        self.source = source
        self.reason = reason
    }

    public static let notReported = RuntimeGuestAddressReadResult(state: .notReported)

    public static func loaded(
        address: String,
        source: RuntimeGuestAddressSource
    ) -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressReadResult(
            state: .loaded,
            address: address,
            source: source
        )
    }

    public static func missing(_ reason: String) -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressReadResult(state: .missing, reason: reason)
    }

    public static func invalid(_ reason: String) -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressReadResult(state: .invalid, reason: reason)
    }

    public static func stale(_ reason: String) -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressReadResult(state: .stale, reason: reason)
    }

    public static func readFailed(_ reason: String) -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressReadResult(state: .readFailed, reason: reason)
    }

    public var loadedAddress: String? {
        state == .loaded ? address : nil
    }

    public var failureStatusText: String {
        switch state {
        case .notReported:
            return RuntimeHTTPStatusText.notRead
        case .loaded:
            return "loaded"
        case .missing:
            return RuntimeHTTPStatusText.missingVMIP
        case .invalid:
            return reason.map { "invalid-guest-address:\($0)" } ?? "invalid-guest-address"
        case .stale:
            return reason.map { "stale-guest-address:\($0)" } ?? "stale-guest-address"
        case .readFailed:
            return reason.map { "guest-address-read-failed:\($0)" } ?? "guest-address-read-failed"
        }
    }
}
