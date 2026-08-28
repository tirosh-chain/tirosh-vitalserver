public enum PlatformAgentUpdateBootstrapVerifiedSelectionContract {
    public static let schemaVersion =
        "vitalserver.platform-agent-update-bootstrap-verified-selection/v2"
    public static let producer = "MacPlatformAgent"
    public static let directoryName =
        "platform-agent-update-bootstrap-selection"
    public static let fileName = "current.json"

    public static let stateVerified = "verified"
    public static let stateApplyCommitted = "applyCommitted"
    public static let stateSpent = "spent"
}

public struct PlatformAgentUpdateBootstrapVerifiedSelection:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: String
    public let producer: String
    public let selectionId: String
    public let verificationInvocationId: String
    public let updateId: String
    public let canonicalPayloadSHA256: String
    public let observedBundlePath: String
    public let state: String
    public let boundRequestId: String?
    public let observedAt: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case producer
        case selectionId
        case verificationInvocationId
        case updateId
        case canonicalPayloadSHA256
        case observedBundlePath
        case state
        case boundRequestId
        case observedAt
    }

    public init(
        schemaVersion: String,
        producer: String,
        selectionId: String,
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String,
        observedBundlePath: String,
        state: String,
        boundRequestId: String? = nil,
        observedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.producer = producer
        self.selectionId = selectionId
        self.verificationInvocationId = verificationInvocationId
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
        self.observedBundlePath = observedBundlePath
        self.state = state
        self.boundRequestId = boundRequestId
        self.observedAt = observedAt
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "PlatformAgentUpdateBootstrapVerifiedSelection"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
            producer: try container.decode(String.self, forKey: .producer),
            selectionId: try container.decode(String.self, forKey: .selectionId),
            verificationInvocationId: try container.decode(
                String.self,
                forKey: .verificationInvocationId
            ),
            updateId: try container.decode(String.self, forKey: .updateId),
            canonicalPayloadSHA256: try container.decode(
                String.self,
                forKey: .canonicalPayloadSHA256
            ),
            observedBundlePath: try container.decode(
                String.self,
                forKey: .observedBundlePath
            ),
            state: try container.decode(String.self, forKey: .state),
            boundRequestId: try Self.decodePresentNonNull(
                container,
                forKey: .boundRequestId
            ),
            observedAt: try container.decode(String.self, forKey: .observedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(producer, forKey: .producer)
        try container.encode(selectionId, forKey: .selectionId)
        try container.encode(
            verificationInvocationId,
            forKey: .verificationInvocationId
        )
        try container.encode(updateId, forKey: .updateId)
        try container.encode(
            canonicalPayloadSHA256,
            forKey: .canonicalPayloadSHA256
        )
        try container.encode(observedBundlePath, forKey: .observedBundlePath)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(boundRequestId, forKey: .boundRequestId)
        try container.encode(observedAt, forKey: .observedAt)
    }

    private static func decodePresentNonNull(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        guard container.contains(key) else {
            return nil
        }
        if try container.decodeNil(forKey: key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(key.rawValue) must not be null"
            )
        }
        return try container.decode(String.self, forKey: key)
    }

    public var journalCorrelation:
        UpdateBootstrapPlatformAgentSelectionCorrelation?
    {
        switch state {
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .stateApplyCommitted,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateSpent:
            return UpdateBootstrapPlatformAgentSelectionCorrelation(
                selectionId: selectionId,
                verificationInvocationId: verificationInvocationId,
                updateId: updateId,
                canonicalPayloadSHA256: canonicalPayloadSHA256
            )
        default:
            return nil
        }
    }
}
