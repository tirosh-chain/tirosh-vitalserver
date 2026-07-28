import Foundation

public struct RuntimeGuestRelease: Codable, Equatable, Sendable {
    public let identity: String
    public let archive: String
    public let digest: String

    public init(identity: String, archive: String, digest: String) {
        self.identity = identity
        self.archive = archive
        self.digest = digest
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case archive
        case digest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decode(String.self, forKey: .identity)
        let archive = try container.decode(String.self, forKey: .archive)
        guard !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !archive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw DecodingError.dataCorruptedError(
                forKey: identity.isEmpty ? .identity : .archive,
                in: container,
                debugDescription: "Guest release identity and archive must not be empty."
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
                debugDescription: "Guest release digest must be canonical SHA-256."
            )
        }
        self.init(identity: identity, archive: archive, digest: digest)
    }
}

public struct RuntimeGuestReleaseFailure: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum RuntimeGuestReleaseReadState: String, Codable, Sendable {
    case available
    case unavailable
}

public struct RuntimeGuestReleaseRead: Codable, Equatable, Sendable {
    public let state: RuntimeGuestReleaseReadState
    public let release: RuntimeGuestRelease?
    public let observedAt: String
    public let failure: RuntimeGuestReleaseFailure?

    public init(
        state: RuntimeGuestReleaseReadState,
        release: RuntimeGuestRelease?,
        observedAt: String,
        failure: RuntimeGuestReleaseFailure?
    ) {
        self.state = state
        self.release = release
        self.observedAt = observedAt
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case release
        case observedAt
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(
            RuntimeGuestReleaseReadState.self,
            forKey: .state
        )
        let release = try container.decodeIfPresent(
            RuntimeGuestRelease.self,
            forKey: .release
        )
        let failure = try container.decodeIfPresent(
            RuntimeGuestReleaseFailure.self,
            forKey: .failure
        )
        let validShape = switch state {
        case .available:
            release != nil && failure == nil
        case .unavailable:
            release == nil && failure != nil
        }
        guard validShape else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Guest release read state and evidence disagree."
            )
        }
        self.init(
            state: state,
            release: release,
            observedAt: try container.decode(String.self, forKey: .observedAt),
            failure: failure
        )
    }
}

public struct RuntimeGuestReleaseMutationRequest: Codable, Equatable, Sendable {
    public let expectedActiveIdentity: String
    public let target: RuntimeGuestRelease

    public init(expectedActiveIdentity: String, target: RuntimeGuestRelease) {
        self.expectedActiveIdentity = expectedActiveIdentity
        self.target = target
    }
}

public enum RuntimeGuestReleaseCommand: String, Codable, Sendable {
    case apply
    case rollback
}

public enum RuntimeGuestReleaseOperationState: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case unavailable
}

public struct RuntimeGuestReleaseOperation: Codable, Equatable, Sendable {
    public let operationId: String
    public let command: RuntimeGuestReleaseCommand
    public let expectedActiveIdentity: String
    public let target: RuntimeGuestRelease
    public let state: RuntimeGuestReleaseOperationState
    public let createdAt: String
    public let updatedAt: String
    public let failure: RuntimeGuestReleaseFailure?

    public init(
        operationId: String,
        command: RuntimeGuestReleaseCommand,
        expectedActiveIdentity: String,
        target: RuntimeGuestRelease,
        state: RuntimeGuestReleaseOperationState,
        createdAt: String,
        updatedAt: String,
        failure: RuntimeGuestReleaseFailure?
    ) {
        self.operationId = operationId
        self.command = command
        self.expectedActiveIdentity = expectedActiveIdentity
        self.target = target
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case operationId
        case command
        case expectedActiveIdentity
        case target
        case state
        case createdAt
        case updatedAt
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operationId = try container.decode(String.self, forKey: .operationId)
        let expectedActiveIdentity = try container.decode(
            String.self,
            forKey: .expectedActiveIdentity
        )
        guard !operationId.isEmpty, !expectedActiveIdentity.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: operationId.isEmpty ? .operationId : .expectedActiveIdentity,
                in: container,
                debugDescription: "Guest release operation identities must not be empty."
            )
        }
        let state = try container.decode(
            RuntimeGuestReleaseOperationState.self,
            forKey: .state
        )
        let failure = try container.decodeIfPresent(
            RuntimeGuestReleaseFailure.self,
            forKey: .failure
        )
        let requiresFailure = state == .failed || state == .unavailable
        guard requiresFailure == (failure != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Guest release operation state and failure disagree."
            )
        }
        self.init(
            operationId: operationId,
            command: try container.decode(
                RuntimeGuestReleaseCommand.self,
                forKey: .command
            ),
            expectedActiveIdentity: expectedActiveIdentity,
            target: try container.decode(
                RuntimeGuestRelease.self,
                forKey: .target
            ),
            state: state,
            createdAt: try container.decode(String.self, forKey: .createdAt),
            updatedAt: try container.decode(String.self, forKey: .updatedAt),
            failure: failure
        )
    }
}
