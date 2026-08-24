public enum UpdateBootstrapVerificationReceiptContract {
    public static let schemaVersion =
        "vitalserver.update-bootstrap-verification-receipt/v1"
    public static let command = "verify-update-bootstrap"
    public static let directoryName = "update-bootstrap-verification"

    public static func fileName(updateId: String) -> String {
        "\(updateId).json"
    }
}

public struct UpdateBootstrapVerificationReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let command: String
    public let updateId: String
    public let canonicalPayloadSHA256: String
    public let resolvedRuntimeHome: String
    public let trustStorePath: String
    public let observedAt: String
    public let uid: UInt32
    public let euid: UInt32

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case command
        case updateId
        case canonicalPayloadSHA256
        case resolvedRuntimeHome
        case trustStorePath
        case observedAt
        case uid
        case euid
    }

    public init(
        schemaVersion: String,
        command: String,
        updateId: String,
        canonicalPayloadSHA256: String,
        resolvedRuntimeHome: String,
        trustStorePath: String,
        observedAt: String,
        uid: UInt32,
        euid: UInt32
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
        self.resolvedRuntimeHome = resolvedRuntimeHome
        self.trustStorePath = trustStorePath
        self.observedAt = observedAt
        self.uid = uid
        self.euid = euid
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapVerificationReceipt"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
            command: try container.decode(String.self, forKey: .command),
            updateId: try container.decode(String.self, forKey: .updateId),
            canonicalPayloadSHA256: try container.decode(
                String.self,
                forKey: .canonicalPayloadSHA256
            ),
            resolvedRuntimeHome: try container.decode(
                String.self,
                forKey: .resolvedRuntimeHome
            ),
            trustStorePath: try container.decode(
                String.self,
                forKey: .trustStorePath
            ),
            observedAt: try container.decode(String.self, forKey: .observedAt),
            uid: try container.decode(UInt32.self, forKey: .uid),
            euid: try container.decode(UInt32.self, forKey: .euid)
        )
    }
}
