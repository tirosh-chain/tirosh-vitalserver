import Foundation

public enum ProductUpdateExecutionContract {
    public static let schemaVersion =
        "vitalserver.product-update-execution/v1"
    public static let layerEffectInvocationSchemaVersion =
        "vitalserver.product-update-layer-effect-invocation/v1"
}

public struct ProductUpdateIssue: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let dependency: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case message
        case retryable
        case dependency
    }

    public init(
        code: String,
        message: String,
        retryable: Bool,
        dependency: String
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.dependency = dependency
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateIssue"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            code: try container.decode(String.self, forKey: .code),
            message: try container.decode(String.self, forKey: .message),
            retryable: try container.decode(Bool.self, forKey: .retryable),
            dependency: try container.decode(String.self, forKey: .dependency)
        )
    }
}

public struct ProductUpdateEvidenceReference: Codable, Equatable, Sendable {
    public let kind: String
    public let id: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case id
    }

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateEvidenceReference"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(String.self, forKey: .kind),
            id: try container.decode(String.self, forKey: .id)
        )
    }
}

public enum ProductUpdateLayerEffectOperation: String, Codable, Equatable, Sendable {
    case apply
    case rollback
}

public enum ProductUpdateLayerEffectState: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case unavailable
    case unsupported
}

public struct ProductUpdateLayerEffectRequest: Equatable, Sendable {
    public let updateId: String
    public let layer: UpdateLayer
    public let effectExecutor: ProductUpdateLayerEffectExecutor
    public let operation: ProductUpdateLayerEffectOperation
    public let artifact: UpdateBootstrapArtifact

    public init(
        updateId: String,
        layer: UpdateLayer,
        effectExecutor: ProductUpdateLayerEffectExecutor,
        operation: ProductUpdateLayerEffectOperation,
        artifact: UpdateBootstrapArtifact
    ) {
        self.updateId = updateId
        self.layer = layer
        self.effectExecutor = effectExecutor
        self.operation = operation
        self.artifact = artifact
    }
}

public struct ProductUpdateLayerEffectInvocation:
    Codable, Equatable, Sendable
{
    public let schemaVersion: String
    public let updateId: String
    public let layer: UpdateLayer
    public let effectExecutorId: String
    public let operation: ProductUpdateLayerEffectOperation
    public let artifactRelativePath: String
    public let artifactPath: String
    public let artifactSHA256: String
    public let artifactSizeBytes: Int
    public let artifactMediaType: String
    public let configurationRelativePath: String
    public let configurationPath: String
    public let configurationSHA256: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case updateId
        case layer
        case effectExecutorId
        case operation
        case artifactRelativePath
        case artifactPath
        case artifactSHA256 = "artifactSha256"
        case artifactSizeBytes
        case artifactMediaType
        case configurationRelativePath
        case configurationPath
        case configurationSHA256 = "configurationSha256"
    }

    public init(
        request: ProductUpdateLayerEffectRequest,
        artifactPath: String,
        configurationPath: String
    ) {
        schemaVersion =
            ProductUpdateExecutionContract.layerEffectInvocationSchemaVersion
        updateId = request.updateId
        layer = request.layer
        effectExecutorId = request.effectExecutor.id
        operation = request.operation
        artifactRelativePath = request.artifact.relativePath
        self.artifactPath = artifactPath
        artifactSHA256 = request.artifact.sha256
        artifactSizeBytes = request.artifact.sizeBytes
        artifactMediaType = request.artifact.mediaType
        configurationRelativePath =
            request.effectExecutor.configurationArtifact.relativePath
        self.configurationPath = configurationPath
        configurationSHA256 =
            request.effectExecutor.configurationArtifact.sha256
    }

    public init(
        schemaVersion: String,
        updateId: String,
        layer: UpdateLayer,
        effectExecutorId: String,
        operation: ProductUpdateLayerEffectOperation,
        artifactRelativePath: String,
        artifactPath: String,
        artifactSHA256: String,
        artifactSizeBytes: Int,
        artifactMediaType: String,
        configurationRelativePath: String,
        configurationPath: String,
        configurationSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.updateId = updateId
        self.layer = layer
        self.effectExecutorId = effectExecutorId
        self.operation = operation
        self.artifactRelativePath = artifactRelativePath
        self.artifactPath = artifactPath
        self.artifactSHA256 = artifactSHA256
        self.artifactSizeBytes = artifactSizeBytes
        self.artifactMediaType = artifactMediaType
        self.configurationRelativePath = configurationRelativePath
        self.configurationPath = configurationPath
        self.configurationSHA256 = configurationSHA256
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateLayerEffectInvocation"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
            updateId: try container.decode(String.self, forKey: .updateId),
            layer: try container.decode(UpdateLayer.self, forKey: .layer),
            effectExecutorId: try container.decode(
                String.self,
                forKey: .effectExecutorId
            ),
            operation: try container.decode(
                ProductUpdateLayerEffectOperation.self,
                forKey: .operation
            ),
            artifactRelativePath: try container.decode(
                String.self,
                forKey: .artifactRelativePath
            ),
            artifactPath: try container.decode(
                String.self,
                forKey: .artifactPath
            ),
            artifactSHA256: try container.decode(
                String.self,
                forKey: .artifactSHA256
            ),
            artifactSizeBytes: try container.decode(
                Int.self,
                forKey: .artifactSizeBytes
            ),
            artifactMediaType: try container.decode(
                String.self,
                forKey: .artifactMediaType
            ),
            configurationRelativePath: try container.decode(
                String.self,
                forKey: .configurationRelativePath
            ),
            configurationPath: try container.decode(
                String.self,
                forKey: .configurationPath
            ),
            configurationSHA256: try container.decode(
                String.self,
                forKey: .configurationSHA256
            )
        )
    }
}

public struct ProductUpdateLayerEffectReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let updateId: String
    public let layer: UpdateLayer
    public let effectExecutorId: String
    public let operation: ProductUpdateLayerEffectOperation
    public let artifactSHA256: String
    public let state: ProductUpdateLayerEffectState
    public let observedAt: String
    public let evidence: ProductUpdateEvidenceReference
    public let issue: ProductUpdateIssue?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case updateId
        case layer
        case effectExecutorId
        case operation
        case artifactSHA256 = "artifactSha256"
        case state
        case observedAt
        case evidence
        case issue
    }

    public init(
        schemaVersion: String,
        updateId: String,
        layer: UpdateLayer,
        effectExecutorId: String,
        operation: ProductUpdateLayerEffectOperation,
        artifactSHA256: String,
        state: ProductUpdateLayerEffectState,
        observedAt: String,
        evidence: ProductUpdateEvidenceReference,
        issue: ProductUpdateIssue?
    ) {
        self.schemaVersion = schemaVersion
        self.updateId = updateId
        self.layer = layer
        self.effectExecutorId = effectExecutorId
        self.operation = operation
        self.artifactSHA256 = artifactSHA256
        self.state = state
        self.observedAt = observedAt
        self.evidence = evidence
        self.issue = issue
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateLayerEffectReceipt"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            updateId: try container.decode(String.self, forKey: .updateId),
            layer: try container.decode(UpdateLayer.self, forKey: .layer),
            effectExecutorId: try container.decode(
                String.self,
                forKey: .effectExecutorId
            ),
            operation: try container.decode(
                ProductUpdateLayerEffectOperation.self,
                forKey: .operation
            ),
            artifactSHA256: try container.decode(
                String.self,
                forKey: .artifactSHA256
            ),
            state: try container.decode(
                ProductUpdateLayerEffectState.self,
                forKey: .state
            ),
            observedAt: try container.decode(String.self, forKey: .observedAt),
            evidence: try container.decode(
                ProductUpdateEvidenceReference.self,
                forKey: .evidence
            ),
            issue: try container.decodeIfPresent(
                ProductUpdateIssue.self,
                forKey: .issue
            )
        )
    }
}

public enum ProductUpdateLayerEffectExecutionResult: Equatable, Sendable {
    case completed(ProductUpdateLayerEffectReceipt)
    case unavailable(reason: String)
    case failed(reason: String)
}

public struct ProductUpdateLayerExecutionEvidence: Codable, Equatable, Sendable {
    public let layer: UpdateLayer
    public let state: ProductUpdateLayerEffectState
    public let artifactSHA256: String
    public let observedAt: String
    public let evidence: ProductUpdateEvidenceReference
    public let issue: ProductUpdateIssue?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case layer
        case state
        case artifactSHA256 = "artifactSha256"
        case observedAt
        case evidence
        case issue
    }

    public init(receipt: ProductUpdateLayerEffectReceipt) {
        layer = receipt.layer
        state = receipt.state
        artifactSHA256 = receipt.artifactSHA256
        observedAt = receipt.observedAt
        evidence = receipt.evidence
        issue = receipt.issue
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateLayerExecutionEvidence"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layer = try container.decode(UpdateLayer.self, forKey: .layer)
        state = try container.decode(
            ProductUpdateLayerEffectState.self,
            forKey: .state
        )
        artifactSHA256 = try container.decode(
            String.self,
            forKey: .artifactSHA256
        )
        observedAt = try container.decode(String.self, forKey: .observedAt)
        evidence = try container.decode(
            ProductUpdateEvidenceReference.self,
            forKey: .evidence
        )
        issue = try container.decodeIfPresent(
            ProductUpdateIssue.self,
            forKey: .issue
        )
    }
}

public enum ProductUpdateRollbackState: String, Codable, Equatable, Sendable {
    case notRequired = "not-required"
    case succeeded
    case failed
    case notAttempted = "not-attempted"
}

public struct ProductUpdateRollbackEvidence: Codable, Equatable, Sendable {
    public let state: ProductUpdateRollbackState
    public let observedAt: String
    public let evidence: ProductUpdateEvidenceReference?
    public let issue: ProductUpdateIssue?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case state
        case observedAt
        case evidence
        case issue
    }

    public init(
        state: ProductUpdateRollbackState,
        observedAt: String,
        evidence: ProductUpdateEvidenceReference?,
        issue: ProductUpdateIssue?
    ) {
        self.state = state
        self.observedAt = observedAt
        self.evidence = evidence
        self.issue = issue
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateRollbackEvidence"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            state: try container.decode(
                ProductUpdateRollbackState.self,
                forKey: .state
            ),
            observedAt: try container.decode(
                String.self,
                forKey: .observedAt
            ),
            evidence: try container.decodeIfPresent(
                ProductUpdateEvidenceReference.self,
                forKey: .evidence
            ),
            issue: try container.decodeIfPresent(
                ProductUpdateIssue.self,
                forKey: .issue
            )
        )
    }
}

public enum ProductUpdateExecutionState: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

public struct ProductUpdateExecutionReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let updateId: String
    public let requestId: String
    public let bootstrapEnvelopeId: String
    public let updateSpecificationSHA256: String
    public let state: ProductUpdateExecutionState
    public let startedAt: String
    public let finishedAt: String
    public let layerEvidence: [ProductUpdateLayerExecutionEvidence]
    public let rollback: ProductUpdateRollbackEvidence
    public let failure: ProductUpdateIssue?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case updateId
        case requestId
        case bootstrapEnvelopeId
        case updateSpecificationSHA256 = "updateSpecificationSha256"
        case state
        case startedAt
        case finishedAt
        case layerEvidence
        case rollback
        case failure
    }

    public init(
        schemaVersion: String,
        updateId: String,
        requestId: String,
        bootstrapEnvelopeId: String,
        updateSpecificationSHA256: String,
        state: ProductUpdateExecutionState,
        startedAt: String,
        finishedAt: String,
        layerEvidence: [ProductUpdateLayerExecutionEvidence],
        rollback: ProductUpdateRollbackEvidence,
        failure: ProductUpdateIssue?
    ) {
        self.schemaVersion = schemaVersion
        self.updateId = updateId
        self.requestId = requestId
        self.bootstrapEnvelopeId = bootstrapEnvelopeId
        self.updateSpecificationSHA256 = updateSpecificationSHA256
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.layerEvidence = layerEvidence
        self.rollback = rollback
        self.failure = failure
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateExecutionReport"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
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
            state: try container.decode(
                ProductUpdateExecutionState.self,
                forKey: .state
            ),
            startedAt: try container.decode(String.self, forKey: .startedAt),
            finishedAt: try container.decode(String.self, forKey: .finishedAt),
            layerEvidence: try container.decode(
                [ProductUpdateLayerExecutionEvidence].self,
                forKey: .layerEvidence
            ),
            rollback: try container.decode(
                ProductUpdateRollbackEvidence.self,
                forKey: .rollback
            ),
            failure: try container.decodeIfPresent(
                ProductUpdateIssue.self,
                forKey: .failure
            )
        )
    }
}
