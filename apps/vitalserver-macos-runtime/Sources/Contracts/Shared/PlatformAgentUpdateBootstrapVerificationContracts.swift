public enum PlatformAgentUpdateBootstrapVerificationContract {
    public static let schemaVersion =
        "vitalserver.platform-agent-update-bootstrap-verification/v1"
    public static let producer = "MacPlatformAgent"
    public static let directoryName =
        "platform-agent-update-bootstrap-verification"

    public static let stateInvoked = "invoked"
    public static let stateSpawnFailed = "spawnFailed"
    public static let stateCommandFailed = "commandFailed"
    public static let stateBindingMissing = "bindingMissing"
    public static let stateBindingInspectionFailed = "bindingInspectionFailed"
    public static let stateBindingPermissionDenied = "bindingPermissionDenied"
    public static let stateBindingReadFailed = "bindingReadFailed"
    public static let stateBindingDecodeFailed = "bindingDecodeFailed"
    public static let stateBindingUnexpectedPathState =
        "bindingUnexpectedPathState"
    public static let stateBindingInvalid = "bindingInvalid"
    public static let stateBindingIdentityMismatch = "bindingIdentityMismatch"
    public static let stateSucceeded = "succeeded"

    public static func fileName(verificationInvocationId: String) -> String {
        "\(verificationInvocationId).json"
    }
}

public struct PlatformAgentUpdateBootstrapVerificationEvidence:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: String
    public let producer: String
    public let verificationInvocationId: String
    public let bundlePath: String
    public let observedAt: String
    public let state: String
    public let updateId: String?
    public let canonicalPayloadSHA256: String?
    public let exitCode: Int32?
    public let spawnFailureReason: String?
    public let bindingPath: String?
    public let bindingFailureReason: String?
    public let bindingPathState: String?
    public let identityField: String?
    public let identityExpected: String?
    public let identityActual: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case producer
        case verificationInvocationId
        case bundlePath
        case observedAt
        case state
        case updateId
        case canonicalPayloadSHA256
        case exitCode
        case spawnFailureReason
        case bindingPath
        case bindingFailureReason
        case bindingPathState
        case identityField
        case identityExpected
        case identityActual
    }

    public init(
        schemaVersion: String,
        producer: String,
        verificationInvocationId: String,
        bundlePath: String,
        observedAt: String,
        state: String,
        updateId: String? = nil,
        canonicalPayloadSHA256: String? = nil,
        exitCode: Int32? = nil,
        spawnFailureReason: String? = nil,
        bindingPath: String? = nil,
        bindingFailureReason: String? = nil,
        bindingPathState: String? = nil,
        identityField: String? = nil,
        identityExpected: String? = nil,
        identityActual: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.producer = producer
        self.verificationInvocationId = verificationInvocationId
        self.bundlePath = bundlePath
        self.observedAt = observedAt
        self.state = state
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
        self.exitCode = exitCode
        self.spawnFailureReason = spawnFailureReason
        self.bindingPath = bindingPath
        self.bindingFailureReason = bindingFailureReason
        self.bindingPathState = bindingPathState
        self.identityField = identityField
        self.identityExpected = identityExpected
        self.identityActual = identityActual
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "PlatformAgentUpdateBootstrapVerificationEvidence"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
            producer: try container.decode(String.self, forKey: .producer),
            verificationInvocationId: try container.decode(
                String.self,
                forKey: .verificationInvocationId
            ),
            bundlePath: try container.decode(String.self, forKey: .bundlePath),
            observedAt: try container.decode(String.self, forKey: .observedAt),
            state: try container.decode(String.self, forKey: .state),
            updateId: try Self.decodePresentNonNull(
                container,
                forKey: .updateId
            ),
            canonicalPayloadSHA256: try Self.decodePresentNonNull(
                container,
                forKey: .canonicalPayloadSHA256
            ),
            exitCode: try Self.decodePresentNonNull(
                container,
                forKey: .exitCode
            ),
            spawnFailureReason: try Self.decodePresentNonNull(
                container,
                forKey: .spawnFailureReason
            ),
            bindingPath: try Self.decodePresentNonNull(
                container,
                forKey: .bindingPath
            ),
            bindingFailureReason: try Self.decodePresentNonNull(
                container,
                forKey: .bindingFailureReason
            ),
            bindingPathState: try Self.decodePresentNonNull(
                container,
                forKey: .bindingPathState
            ),
            identityField: try Self.decodePresentNonNull(
                container,
                forKey: .identityField
            ),
            identityExpected: try Self.decodePresentNonNull(
                container,
                forKey: .identityExpected
            ),
            identityActual: try Self.decodePresentNonNull(
                container,
                forKey: .identityActual
            )
        )
    }

    private static func decodePresentNonNull<T: Decodable>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> T? {
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
        return try container.decode(T.self, forKey: key)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(producer, forKey: .producer)
        try container.encode(
            verificationInvocationId,
            forKey: .verificationInvocationId
        )
        try container.encode(bundlePath, forKey: .bundlePath)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(updateId, forKey: .updateId)
        try container.encodeIfPresent(
            canonicalPayloadSHA256,
            forKey: .canonicalPayloadSHA256
        )
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        try container.encodeIfPresent(
            spawnFailureReason,
            forKey: .spawnFailureReason
        )
        try container.encodeIfPresent(bindingPath, forKey: .bindingPath)
        try container.encodeIfPresent(
            bindingFailureReason,
            forKey: .bindingFailureReason
        )
        try container.encodeIfPresent(
            bindingPathState,
            forKey: .bindingPathState
        )
        try container.encodeIfPresent(identityField, forKey: .identityField)
        try container.encodeIfPresent(
            identityExpected,
            forKey: .identityExpected
        )
        try container.encodeIfPresent(identityActual, forKey: .identityActual)
    }
}
