import Foundation

public struct ProductUpdateSpecification: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let bootstrapEnvelopeId: String
    public let layerPlan: [ProductUpdateLayerPlan]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case bootstrapEnvelopeId
        case layerPlan
    }

    public init(
        schemaVersion: String,
        id: String,
        bootstrapEnvelopeId: String,
        layerPlan: [ProductUpdateLayerPlan]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.bootstrapEnvelopeId = bootstrapEnvelopeId
        self.layerPlan = layerPlan
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateSpecification"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            id: try container.decode(String.self, forKey: .id),
            bootstrapEnvelopeId: try container.decode(
                String.self,
                forKey: .bootstrapEnvelopeId
            ),
            layerPlan: try container.decode(
                [ProductUpdateLayerPlan].self,
                forKey: .layerPlan
            )
        )
    }
}

public struct ProductUpdateLayerPlan: Codable, Equatable, Sendable {
    public let layer: UpdateLayer
    public let dependsOn: [UpdateLayer]
    public let artifact: UpdateBootstrapArtifact
    public let effectExecutor: ProductUpdateLayerEffectExecutor
    public let rollback: ProductUpdateLayerRollbackPlan

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case layer
        case dependsOn
        case artifact
        case effectExecutor
        case rollback
    }

    public init(
        layer: UpdateLayer,
        dependsOn: [UpdateLayer],
        artifact: UpdateBootstrapArtifact,
        effectExecutor: ProductUpdateLayerEffectExecutor,
        rollback: ProductUpdateLayerRollbackPlan
    ) {
        self.layer = layer
        self.dependsOn = dependsOn
        self.artifact = artifact
        self.effectExecutor = effectExecutor
        self.rollback = rollback
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateLayerPlan"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            layer: try container.decode(UpdateLayer.self, forKey: .layer),
            dependsOn: try container.decode(
                [UpdateLayer].self,
                forKey: .dependsOn
            ),
            artifact: try container.decode(
                UpdateBootstrapArtifact.self,
                forKey: .artifact
            ),
            effectExecutor: try container.decode(
                ProductUpdateLayerEffectExecutor.self,
                forKey: .effectExecutor
            ),
            rollback: try container.decode(
                ProductUpdateLayerRollbackPlan.self,
                forKey: .rollback
            )
        )
    }
}

public struct ProductUpdateLayerEffectExecutor: Codable, Equatable, Sendable {
    public let id: String
    public let relativePath: String
    public let sha256: String
    public let sizeBytes: Int
    public let mediaType: String
    public let configurationArtifact: UpdateBootstrapArtifact

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case relativePath
        case sha256
        case sizeBytes
        case mediaType
        case configurationArtifact
    }

    public init(
        id: String,
        relativePath: String,
        sha256: String,
        sizeBytes: Int,
        mediaType: String,
        configurationArtifact: UpdateBootstrapArtifact
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.mediaType = mediaType
        self.configurationArtifact = configurationArtifact
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateLayerEffectExecutor"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            relativePath: try container.decode(String.self, forKey: .relativePath),
            sha256: try container.decode(String.self, forKey: .sha256),
            sizeBytes: try container.decode(Int.self, forKey: .sizeBytes),
            mediaType: try container.decode(String.self, forKey: .mediaType),
            configurationArtifact: try container.decode(
                UpdateBootstrapArtifact.self,
                forKey: .configurationArtifact
            )
        )
    }
}

public enum ProductUpdateRollbackAvailability: String, Codable, Equatable, Sendable {
    case available
    case unsupported
}

public struct ProductUpdateLayerRollbackPlan: Codable, Equatable, Sendable {
    public let state: ProductUpdateRollbackAvailability
    public let artifact: UpdateBootstrapArtifact?
    public let reason: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case state
        case artifact
        case reason
    }

    public init(
        state: ProductUpdateRollbackAvailability,
        artifact: UpdateBootstrapArtifact?,
        reason: String?
    ) {
        self.state = state
        self.artifact = artifact
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "ProductUpdateLayerRollbackPlan"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            state: try container.decode(
                ProductUpdateRollbackAvailability.self,
                forKey: .state
            ),
            artifact: try container.decodeIfPresent(
                UpdateBootstrapArtifact.self,
                forKey: .artifact
            ),
            reason: try container.decodeIfPresent(String.self, forKey: .reason)
        )
    }
}

public struct ProductUpdateExecutionPlan: Equatable, Sendable {
    public let updateId: String
    public let specificationId: String
    public let layerPlan: [ProductUpdateLayerPlan]

    public init(
        updateId: String,
        specificationId: String,
        layerPlan: [ProductUpdateLayerPlan]
    ) {
        self.updateId = updateId
        self.specificationId = specificationId
        self.layerPlan = layerPlan
    }
}
