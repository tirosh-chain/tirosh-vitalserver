public enum UpdateBootstrapVerificationInvocationBindingContract {
    public static let schemaVersion =
        "vitalserver.update-bootstrap-verification-invocation-binding/v1"
    public static let command = "verify-update-bootstrap"
    public static let directoryName = "invocations"

    public static func fileName(verificationInvocationId: String) -> String {
        "\(verificationInvocationId).json"
    }
}

public struct UpdateBootstrapVerificationInvocationBinding:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: String
    public let command: String
    public let verificationInvocationId: String
    public let updateId: String
    public let canonicalPayloadSHA256: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case command
        case verificationInvocationId
        case updateId
        case canonicalPayloadSHA256
    }

    public init(
        schemaVersion: String,
        command: String,
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.verificationInvocationId = verificationInvocationId
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapVerificationInvocationBinding"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
            command: try container.decode(String.self, forKey: .command),
            verificationInvocationId: try container.decode(
                String.self,
                forKey: .verificationInvocationId
            ),
            updateId: try container.decode(String.self, forKey: .updateId),
            canonicalPayloadSHA256: try container.decode(
                String.self,
                forKey: .canonicalPayloadSHA256
            )
        )
    }
}
