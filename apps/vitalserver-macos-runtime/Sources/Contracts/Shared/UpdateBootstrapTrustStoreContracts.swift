public struct UpdateBootstrapTrustStore: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let keys: [TrustedUpdatePublisherKey]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case keys
    }

    public init(schemaVersion: String, keys: [TrustedUpdatePublisherKey]) {
        self.schemaVersion = schemaVersion
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapTrustStore"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            keys: try container.decode([TrustedUpdatePublisherKey].self, forKey: .keys)
        )
    }
}

public struct TrustedUpdatePublisherKey: Codable, Equatable, Sendable {
    public let id: String
    public let algorithm: UpdateBootstrapSignatureAlgorithm
    public let publicKey: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case algorithm
        case publicKey
    }

    public init(
        id: String,
        algorithm: UpdateBootstrapSignatureAlgorithm,
        publicKey: String
    ) {
        self.id = id
        self.algorithm = algorithm
        self.publicKey = publicKey
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "TrustedUpdatePublisherKey"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            algorithm: try container.decode(
                UpdateBootstrapSignatureAlgorithm.self,
                forKey: .algorithm
            ),
            publicKey: try container.decode(String.self, forKey: .publicKey)
        )
    }
}
