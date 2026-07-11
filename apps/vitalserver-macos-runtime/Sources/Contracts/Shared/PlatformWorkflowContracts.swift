public enum PlatformWorkflowKind: String, Codable, Equatable, Sendable {
    case updateVerify = "update-verify"
    case updateApply = "update-apply"
    case rollback
    case uninstall
    case supportExport = "support-export"
}

public enum PlatformWorkflowState: String, Codable, Equatable, Sendable {
    case accepted
    case running
    case completed
    case failed
}

public struct PlatformWorkflowRelease: Codable, Equatable, Sendable {
    public let platformVersion: String
    public let runtimeBundleVersion: String

    public init(platformVersion: String, runtimeBundleVersion: String) {
        self.platformVersion = platformVersion
        self.runtimeBundleVersion = runtimeBundleVersion
    }
}

public struct PlatformWorkflowFailure: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct PlatformWorkflowArtifact: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
    public let sizeBytes: Int64

    public init(path: String, sha256: String, sizeBytes: Int64) {
        self.path = path
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }
}

public struct PlatformWorkflowOperation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let operationId: String
    public let kind: PlatformWorkflowKind
    public let state: PlatformWorkflowState
    public let startedAt: String
    public let updatedAt: String
    public let release: PlatformWorkflowRelease?
    public let artifact: PlatformWorkflowArtifact?
    public let failure: PlatformWorkflowFailure?

    public init(
        schemaVersion: Int = 1,
        operationId: String,
        kind: PlatformWorkflowKind,
        state: PlatformWorkflowState,
        startedAt: String,
        updatedAt: String,
        release: PlatformWorkflowRelease?,
        artifact: PlatformWorkflowArtifact? = nil,
        failure: PlatformWorkflowFailure?
    ) {
        self.schemaVersion = schemaVersion
        self.operationId = operationId
        self.kind = kind
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.release = release
        self.artifact = artifact
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, operationId, kind, state, startedAt, updatedAt, release, artifact, failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.release, .artifact, .failure] where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: decoder.codingPath, debugDescription: "Platform workflow requires explicit nullable field \(key.stringValue).")
            )
        }
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        operationId = try container.decode(String.self, forKey: .operationId)
        kind = try container.decode(PlatformWorkflowKind.self, forKey: .kind)
        state = try container.decode(PlatformWorkflowState.self, forKey: .state)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        release = try container.decodeIfPresent(PlatformWorkflowRelease.self, forKey: .release)
        artifact = try container.decodeIfPresent(PlatformWorkflowArtifact.self, forKey: .artifact)
        failure = try container.decodeIfPresent(PlatformWorkflowFailure.self, forKey: .failure)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(kind, forKey: .kind)
        try container.encode(state, forKey: .state)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        if let release { try container.encode(release, forKey: .release) } else { try container.encodeNil(forKey: .release) }
        if let artifact { try container.encode(artifact, forKey: .artifact) } else { try container.encodeNil(forKey: .artifact) }
        if let failure { try container.encode(failure, forKey: .failure) } else { try container.encodeNil(forKey: .failure) }
    }
}

public enum PlatformWorkflowResourceState: String, Codable, Equatable, Sendable {
    case loaded
    case missing
    case unavailable
    case failed
}

public struct PlatformWorkflowResource: Codable, Equatable, Sendable {
    public let state: PlatformWorkflowResourceState
    public let operation: PlatformWorkflowOperation?
    public let readError: String?

    public init(state: PlatformWorkflowResourceState, operation: PlatformWorkflowOperation?, readError: String?) {
        self.state = state
        self.operation = operation
        self.readError = readError
    }
}
