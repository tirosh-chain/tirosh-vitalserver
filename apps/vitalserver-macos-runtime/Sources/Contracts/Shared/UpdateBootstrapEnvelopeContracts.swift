import Foundation

public struct UpdateBootstrapEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let productId: String
    public let target: UpdateBootstrapTarget
    public let targetRelease: UpdateBootstrapRelease
    public let layerOrder: [UpdateLayer]
    public let nextUpdaterArtifact: UpdateBootstrapArtifact
    public let specification: UpdateBootstrapArtifact
    public let signature: UpdateBootstrapSignature
    public let issuedAt: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case productId
        case target
        case targetRelease
        case layerOrder
        case nextUpdaterArtifact
        case specification
        case signature
        case issuedAt
    }

    public init(
        schemaVersion: String,
        id: String,
        productId: String,
        target: UpdateBootstrapTarget,
        targetRelease: UpdateBootstrapRelease,
        layerOrder: [UpdateLayer],
        nextUpdaterArtifact: UpdateBootstrapArtifact,
        specification: UpdateBootstrapArtifact,
        signature: UpdateBootstrapSignature,
        issuedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.productId = productId
        self.target = target
        self.targetRelease = targetRelease
        self.layerOrder = layerOrder
        self.nextUpdaterArtifact = nextUpdaterArtifact
        self.specification = specification
        self.signature = signature
        self.issuedAt = issuedAt
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapEnvelope"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            id: try container.decode(String.self, forKey: .id),
            productId: try container.decode(String.self, forKey: .productId),
            target: try container.decode(UpdateBootstrapTarget.self, forKey: .target),
            targetRelease: try container.decode(UpdateBootstrapRelease.self, forKey: .targetRelease),
            layerOrder: try container.decode([UpdateLayer].self, forKey: .layerOrder),
            nextUpdaterArtifact: try container.decode(UpdateBootstrapArtifact.self, forKey: .nextUpdaterArtifact),
            specification: try container.decode(UpdateBootstrapArtifact.self, forKey: .specification),
            signature: try container.decode(UpdateBootstrapSignature.self, forKey: .signature),
            issuedAt: try container.decode(String.self, forKey: .issuedAt)
        )
    }
}

public struct UpdateBootstrapTarget: Codable, Equatable, Sendable {
    public let platform: UpdateTargetPlatform
    public let architecture: UpdateTargetArchitecture

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case platform
        case architecture
    }

    public init(platform: UpdateTargetPlatform, architecture: UpdateTargetArchitecture) {
        self.platform = platform
        self.architecture = architecture
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapTarget"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            platform: try container.decode(UpdateTargetPlatform.self, forKey: .platform),
            architecture: try container.decode(UpdateTargetArchitecture.self, forKey: .architecture)
        )
    }
}

public enum UpdateTargetPlatform: String, Codable, Equatable, Sendable {
    case macos
    case windows
    case linux
}

public enum UpdateTargetArchitecture: String, Codable, Equatable, Sendable {
    case arm64
    case amd64
}

public struct UpdateBootstrapRelease: Codable, Equatable, Sendable {
    public let productVersion: String
    public let runtimeVersion: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case productVersion
        case runtimeVersion
    }

    public init(productVersion: String, runtimeVersion: String) {
        self.productVersion = productVersion
        self.runtimeVersion = runtimeVersion
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapRelease"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            productVersion: try container.decode(String.self, forKey: .productVersion),
            runtimeVersion: try container.decode(String.self, forKey: .runtimeVersion)
        )
    }
}

public enum UpdateLayer: String, Codable, Equatable, Hashable, Sendable {
    case container
    case guestRuntime = "guest-runtime"
    case hostPlatform = "host-platform"
}

public struct UpdateBootstrapArtifact: Codable, Equatable, Sendable {
    public let id: String
    public let relativePath: String
    public let sha256: String
    public let sizeBytes: Int
    public let mediaType: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case relativePath
        case sha256
        case sizeBytes
        case mediaType
    }

    public init(
        id: String,
        relativePath: String,
        sha256: String,
        sizeBytes: Int,
        mediaType: String
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.mediaType = mediaType
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapArtifact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            relativePath: try container.decode(String.self, forKey: .relativePath),
            sha256: try container.decode(String.self, forKey: .sha256),
            sizeBytes: try container.decode(Int.self, forKey: .sizeBytes),
            mediaType: try container.decode(String.self, forKey: .mediaType)
        )
    }
}

public struct UpdateBootstrapSignature: Codable, Equatable, Sendable {
    public let algorithm: UpdateBootstrapSignatureAlgorithm
    public let keyId: String
    public let signedSha256: String
    public let value: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case algorithm
        case keyId
        case signedSha256
        case value
    }

    public init(
        algorithm: UpdateBootstrapSignatureAlgorithm,
        keyId: String,
        signedSha256: String,
        value: String
    ) {
        self.algorithm = algorithm
        self.keyId = keyId
        self.signedSha256 = signedSha256
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapSignature"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            algorithm: try container.decode(UpdateBootstrapSignatureAlgorithm.self, forKey: .algorithm),
            keyId: try container.decode(String.self, forKey: .keyId),
            signedSha256: try container.decode(String.self, forKey: .signedSha256),
            value: try container.decode(String.self, forKey: .value)
        )
    }
}

public enum UpdateBootstrapSignatureAlgorithm: String, Codable, Equatable, Sendable {
    case ed25519
}

private struct UpdateBootstrapContractKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

func rejectUnknownUpdateBootstrapKeys(
    _ decoder: Decoder,
    allowed: [String],
    type: String
) throws {
    let container = try decoder.container(keyedBy: UpdateBootstrapContractKey.self)
    let allowedKeys = Set(allowed)
    let unknownKeys = container.allKeys
        .map(\.stringValue)
        .filter { !allowedKeys.contains($0) }
        .sorted()
    guard unknownKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "\(type) contains unsupported fields: \(unknownKeys.joined(separator: ","))"
            )
        )
    }
}
