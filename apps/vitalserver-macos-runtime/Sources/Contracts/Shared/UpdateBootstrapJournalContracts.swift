public enum UpdateBootstrapJournalState: String, Codable, Equatable, Sendable {
    case admitted
    case handoffPending = "handoff-pending"
    case running
    case succeeded
    case failed
    case interrupted
}

public enum UpdateBootstrapCompletionOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

public struct UpdateBootstrapCompletionReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let updateId: String
    public let requestId: String
    public let bootstrapEnvelopeId: String
    public let updateSpecificationSHA256: String
    public let expectedJournalRevision: Int
    public let outcome: UpdateBootstrapCompletionOutcome
    public let reportRelativePath: String
    public let reportSHA256: String
    public let failureReason: String?
    public let finishedAt: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case updateId
        case requestId
        case bootstrapEnvelopeId
        case updateSpecificationSHA256
        case expectedJournalRevision
        case outcome
        case reportRelativePath
        case reportSHA256
        case failureReason
        case finishedAt
    }

    public init(
        schemaVersion: String,
        updateId: String,
        requestId: String,
        bootstrapEnvelopeId: String,
        updateSpecificationSHA256: String,
        expectedJournalRevision: Int,
        outcome: UpdateBootstrapCompletionOutcome,
        reportRelativePath: String,
        reportSHA256: String,
        failureReason: String?,
        finishedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.updateId = updateId
        self.requestId = requestId
        self.bootstrapEnvelopeId = bootstrapEnvelopeId
        self.updateSpecificationSHA256 = updateSpecificationSHA256
        self.expectedJournalRevision = expectedJournalRevision
        self.outcome = outcome
        self.reportRelativePath = reportRelativePath
        self.reportSHA256 = reportSHA256
        self.failureReason = failureReason
        self.finishedAt = finishedAt
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapCompletionReceipt"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            updateId: try container.decode(String.self, forKey: .updateId),
            requestId: try container.decode(String.self, forKey: .requestId),
            bootstrapEnvelopeId: try container.decode(
                String.self,
                forKey: .bootstrapEnvelopeId
            ),
            updateSpecificationSHA256: try container.decode(
                String.self,
                forKey: .updateSpecificationSHA256
            ),
            expectedJournalRevision: try container.decode(
                Int.self,
                forKey: .expectedJournalRevision
            ),
            outcome: try container.decode(
                UpdateBootstrapCompletionOutcome.self,
                forKey: .outcome
            ),
            reportRelativePath: try container.decode(
                String.self,
                forKey: .reportRelativePath
            ),
            reportSHA256: try container.decode(
                String.self,
                forKey: .reportSHA256
            ),
            failureReason: try container.decodeIfPresent(
                String.self,
                forKey: .failureReason
            ),
            finishedAt: try container.decode(String.self, forKey: .finishedAt)
        )
    }
}

public struct UpdateBootstrapPlatformAgentSelectionCorrelation:
    Codable,
    Equatable,
    Sendable
{
    public let selectionId: String
    public let verificationInvocationId: String
    public let updateId: String
    public let canonicalPayloadSHA256: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case selectionId
        case verificationInvocationId
        case updateId
        case canonicalPayloadSHA256
    }

    public init(
        selectionId: String,
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String
    ) {
        self.selectionId = selectionId
        self.verificationInvocationId = verificationInvocationId
        self.updateId = updateId
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapPlatformAgentSelectionCorrelation"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectionId: try container.decode(String.self, forKey: .selectionId),
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

public struct UpdateBootstrapJournal: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let journalRevision: Int
    public let operationId: String
    public let targetInstallationId: String
    public let expectedInstallationRevision: Int
    public let requestId: String
    public let envelope: UpdateBootstrapEnvelope
    public let bootstrapSignedSHA256: String
    public let state: UpdateBootstrapJournalState
    public let stagedUpdaterRelativePath: String?
    public let stagedSpecificationRelativePath: String?
    public let completion: UpdateBootstrapCompletionReceipt?
    public let failureReason: String?
    public let createdAt: String
    public let updatedAt: String
    public let platformAgentSelectionCorrelation:
        UpdateBootstrapPlatformAgentSelectionCorrelation?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case journalRevision
        case operationId
        case targetInstallationId
        case expectedInstallationRevision
        case requestId
        case envelope
        case bootstrapSignedSHA256
        case state
        case stagedUpdaterRelativePath
        case stagedSpecificationRelativePath
        case completion
        case failureReason
        case createdAt
        case updatedAt
        case platformAgentSelectionCorrelation
    }

    public init(
        schemaVersion: String,
        id: String,
        journalRevision: Int,
        operationId: String,
        targetInstallationId: String,
        expectedInstallationRevision: Int,
        requestId: String,
        envelope: UpdateBootstrapEnvelope,
        bootstrapSignedSHA256: String,
        state: UpdateBootstrapJournalState,
        stagedUpdaterRelativePath: String?,
        stagedSpecificationRelativePath: String?,
        completion: UpdateBootstrapCompletionReceipt?,
        failureReason: String?,
        createdAt: String,
        updatedAt: String,
        platformAgentSelectionCorrelation:
            UpdateBootstrapPlatformAgentSelectionCorrelation? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.journalRevision = journalRevision
        self.operationId = operationId
        self.targetInstallationId = targetInstallationId
        self.expectedInstallationRevision = expectedInstallationRevision
        self.requestId = requestId
        self.envelope = envelope
        self.bootstrapSignedSHA256 = bootstrapSignedSHA256
        self.state = state
        self.stagedUpdaterRelativePath = stagedUpdaterRelativePath
        self.stagedSpecificationRelativePath = stagedSpecificationRelativePath
        self.completion = completion
        self.failureReason = failureReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.platformAgentSelectionCorrelation =
            platformAgentSelectionCorrelation
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapJournal"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            id: try container.decode(String.self, forKey: .id),
            journalRevision: try container.decode(Int.self, forKey: .journalRevision),
            operationId: try container.decode(String.self, forKey: .operationId),
            targetInstallationId: try container.decode(String.self, forKey: .targetInstallationId),
            expectedInstallationRevision: try container.decode(Int.self, forKey: .expectedInstallationRevision),
            requestId: try container.decode(String.self, forKey: .requestId),
            envelope: try container.decode(
                UpdateBootstrapEnvelope.self,
                forKey: .envelope
            ),
            bootstrapSignedSHA256: try container.decode(
                String.self,
                forKey: .bootstrapSignedSHA256
            ),
            state: try container.decode(
                UpdateBootstrapJournalState.self,
                forKey: .state
            ),
            stagedUpdaterRelativePath: try container.decodeIfPresent(
                String.self,
                forKey: .stagedUpdaterRelativePath
            ),
            stagedSpecificationRelativePath: try container.decodeIfPresent(
                String.self,
                forKey: .stagedSpecificationRelativePath
            ),
            completion: try container.decodeIfPresent(
                UpdateBootstrapCompletionReceipt.self,
                forKey: .completion
            ),
            failureReason: try container.decodeIfPresent(
                String.self,
                forKey: .failureReason
            ),
            createdAt: try container.decode(String.self, forKey: .createdAt),
            updatedAt: try container.decode(String.self, forKey: .updatedAt),
            platformAgentSelectionCorrelation: try Self.decodePresentNonNull(
                container,
                forKey: .platformAgentSelectionCorrelation
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(journalRevision, forKey: .journalRevision)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(targetInstallationId, forKey: .targetInstallationId)
        try container.encode(
            expectedInstallationRevision,
            forKey: .expectedInstallationRevision
        )
        try container.encode(requestId, forKey: .requestId)
        try container.encode(envelope, forKey: .envelope)
        try container.encode(bootstrapSignedSHA256, forKey: .bootstrapSignedSHA256)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(
            stagedUpdaterRelativePath,
            forKey: .stagedUpdaterRelativePath
        )
        try container.encodeIfPresent(
            stagedSpecificationRelativePath,
            forKey: .stagedSpecificationRelativePath
        )
        try container.encodeIfPresent(completion, forKey: .completion)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(
            platformAgentSelectionCorrelation,
            forKey: .platformAgentSelectionCorrelation
        )
    }

    private static func decodePresentNonNull(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> UpdateBootstrapPlatformAgentSelectionCorrelation? {
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
        return try container.decode(
            UpdateBootstrapPlatformAgentSelectionCorrelation.self,
            forKey: key
        )
    }
}
