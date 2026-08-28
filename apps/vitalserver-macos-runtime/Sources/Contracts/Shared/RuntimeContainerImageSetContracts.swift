import Foundation

public struct RuntimeContainerImageSet: Codable, Equatable, Sendable {
    public let identity: String
    public let digest: String

    public init(identity: String, digest: String) {
        self.identity = identity
        self.digest = digest
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case digest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decode(String.self, forKey: .identity)
        guard !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .identity,
                in: container,
                debugDescription: "Container image-set identity must not be empty."
            )
        }
        let digest = try container.decode(String.self, forKey: .digest)
        let hex = String(digest.dropFirst("sha256:".count))
        guard digest.hasPrefix("sha256:"),
              hex.count == 64,
              hex.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .digest,
                in: container,
                debugDescription: "Container image-set digest must be canonical SHA-256."
            )
        }
        self.init(identity: identity, digest: digest)
    }
}

public struct RuntimeContainerImageSetFailure: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum RuntimeContainerImageSetReadState: String, Codable, Sendable {
    case available
    case unavailable
}

public struct RuntimeContainerImageSetRead: Codable, Equatable, Sendable {
    public let state: RuntimeContainerImageSetReadState
    public let imageSet: RuntimeContainerImageSet?
    public let observedAt: String
    public let failure: RuntimeContainerImageSetFailure?

    public init(
        state: RuntimeContainerImageSetReadState,
        imageSet: RuntimeContainerImageSet?,
        observedAt: String,
        failure: RuntimeContainerImageSetFailure?
    ) {
        self.state = state
        self.imageSet = imageSet
        self.observedAt = observedAt
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case imageSet
        case observedAt
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(
            RuntimeContainerImageSetReadState.self,
            forKey: .state
        )
        let imageSet = try container.decodeIfPresent(
            RuntimeContainerImageSet.self,
            forKey: .imageSet
        )
        let observedAt = try container.decode(String.self, forKey: .observedAt)
        let failure = try container.decodeIfPresent(
            RuntimeContainerImageSetFailure.self,
            forKey: .failure
        )
        let validShape = switch state {
        case .available:
            imageSet != nil && failure == nil
        case .unavailable:
            imageSet == nil && failure != nil
        }
        guard validShape else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Container image-set read state and evidence disagree."
            )
        }
        self.init(
            state: state,
            imageSet: imageSet,
            observedAt: observedAt,
            failure: failure
        )
    }
}

public struct RuntimeContainerImageSetMutationRequest: Codable, Equatable, Sendable {
    public let expectedCurrentIdentity: String
    public let target: RuntimeContainerImageSet

    public init(expectedCurrentIdentity: String, target: RuntimeContainerImageSet) {
        self.expectedCurrentIdentity = expectedCurrentIdentity
        self.target = target
    }
}

public enum RuntimeContainerImageSetCommand: String, Codable, Sendable {
    case apply
    case rollback
}

public enum RuntimeContainerImageSetOperationState: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case unavailable
}

public struct RuntimeContainerImageSetOperation: Codable, Equatable, Sendable {
    public let operationId: String
    public let command: RuntimeContainerImageSetCommand
    public let expectedCurrentIdentity: String
    public let target: RuntimeContainerImageSet
    public let state: RuntimeContainerImageSetOperationState
    public let createdAt: String
    public let updatedAt: String
    public let failure: RuntimeContainerImageSetFailure?

    public init(
        operationId: String,
        command: RuntimeContainerImageSetCommand,
        expectedCurrentIdentity: String,
        target: RuntimeContainerImageSet,
        state: RuntimeContainerImageSetOperationState,
        createdAt: String,
        updatedAt: String,
        failure: RuntimeContainerImageSetFailure?
    ) {
        self.operationId = operationId
        self.command = command
        self.expectedCurrentIdentity = expectedCurrentIdentity
        self.target = target
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case operationId
        case command
        case expectedCurrentIdentity
        case target
        case state
        case createdAt
        case updatedAt
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operationId = try container.decode(String.self, forKey: .operationId)
        let expectedCurrentIdentity = try container.decode(
            String.self,
            forKey: .expectedCurrentIdentity
        )
        guard !operationId.isEmpty, !expectedCurrentIdentity.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: operationId.isEmpty ? .operationId : .expectedCurrentIdentity,
                in: container,
                debugDescription: "Container image-set operation identities must not be empty."
            )
        }
        let state = try container.decode(
            RuntimeContainerImageSetOperationState.self,
            forKey: .state
        )
        let failure = try container.decodeIfPresent(
            RuntimeContainerImageSetFailure.self,
            forKey: .failure
        )
        let requiresFailure = state == .failed || state == .unavailable
        guard requiresFailure == (failure != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Container image-set operation state and failure disagree."
            )
        }
        self.init(
            operationId: operationId,
            command: try container.decode(
                RuntimeContainerImageSetCommand.self,
                forKey: .command
            ),
            expectedCurrentIdentity: expectedCurrentIdentity,
            target: try container.decode(
                RuntimeContainerImageSet.self,
                forKey: .target
            ),
            state: state,
            createdAt: try container.decode(String.self, forKey: .createdAt),
            updatedAt: try container.decode(String.self, forKey: .updatedAt),
            failure: failure
        )
    }
}
