public struct UpdateBundleManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let product: String
    public let bundleKind: UpdateBundleKind
    public let channel: UpdateBundleChannel
    public let helperVersion: String
    public let releaseLabel: String
    public let targetPlatform: String
    public let components: [String: String]
    public let minUpdaterVersion: String?
    public let requiresGuestActivation: Bool
    public let requiresTwoPhaseUpdate: Bool
    public let createdAt: String
    public let artifacts: [UpdateBundleArtifact]
    public let migrations: [UpdateBundleMigration]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case product
        case bundleKind
        case channel
        case helperVersion
        case releaseLabel
        case targetPlatform
        case components
        case minUpdaterVersion
        case requiresGuestActivation
        case requiresTwoPhaseUpdate
        case createdAt
        case artifacts
        case migrations
    }

    public init(
        schemaVersion: Int,
        product: String,
        bundleKind: UpdateBundleKind = .productUpdate,
        channel: UpdateBundleChannel = .stable,
        helperVersion: String,
        releaseLabel: String,
        targetPlatform: String,
        components: [String: String],
        minUpdaterVersion: String? = nil,
        requiresGuestActivation: Bool = false,
        requiresTwoPhaseUpdate: Bool = false,
        createdAt: String,
        artifacts: [UpdateBundleArtifact],
        migrations: [UpdateBundleMigration]
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.bundleKind = bundleKind
        self.channel = channel
        self.helperVersion = helperVersion
        self.releaseLabel = releaseLabel
        self.targetPlatform = targetPlatform
        self.components = components
        self.minUpdaterVersion = minUpdaterVersion
        self.requiresGuestActivation = requiresGuestActivation
        self.requiresTwoPhaseUpdate = requiresTwoPhaseUpdate
        self.createdAt = createdAt
        self.artifacts = artifacts
        self.migrations = migrations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            product: try container.decode(String.self, forKey: .product),
            bundleKind: try container.decode(UpdateBundleKind.self, forKey: .bundleKind),
            channel: try container.decode(UpdateBundleChannel.self, forKey: .channel),
            helperVersion: try container.decode(String.self, forKey: .helperVersion),
            releaseLabel: try container.decode(String.self, forKey: .releaseLabel),
            targetPlatform: try container.decode(String.self, forKey: .targetPlatform),
            components: try container.decode([String: String].self, forKey: .components),
            minUpdaterVersion: try container.decodeIfPresent(String.self, forKey: .minUpdaterVersion),
            requiresGuestActivation: try container.decodeIfPresent(Bool.self, forKey: .requiresGuestActivation) ?? false,
            requiresTwoPhaseUpdate: try container.decodeIfPresent(Bool.self, forKey: .requiresTwoPhaseUpdate) ?? false,
            createdAt: try container.decode(String.self, forKey: .createdAt),
            artifacts: try container.decode([UpdateBundleArtifact].self, forKey: .artifacts),
            migrations: try container.decode([UpdateBundleMigration].self, forKey: .migrations)
        )
    }

    public var version: String {
        releaseLabel
    }

    public var runtimeVersion: String {
        components[UpdateBundleComponentKey.updater.rawValue] ?? helperVersion
    }
}

public struct UpdateBundleFileVerification: Equatable, Sendable {
    public let name: String
    public let checksumKey: String
    public let expectedSHA256: String
    public let expectedSize: Int

    public init(name: String, checksumKey: String, expectedSHA256: String, expectedSize: Int) {
        self.name = name
        self.checksumKey = checksumKey
        self.expectedSHA256 = expectedSHA256
        self.expectedSize = expectedSize
    }
}

public struct UpdateBundleVerificationPlan: Equatable, Sendable {
    public let artifactFiles: [UpdateBundleFileVerification]
    public let migrationFiles: [UpdateBundleFileVerification]

    public init(
        artifactFiles: [UpdateBundleFileVerification],
        migrationFiles: [UpdateBundleFileVerification]
    ) {
        self.artifactFiles = artifactFiles
        self.migrationFiles = migrationFiles
    }
}

public enum UpdateBundleChannel: Codable, Equatable, Sendable {
    case stable
    case dev
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "stable":
            self = .stable
        case "dev":
            self = .dev
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .stable:
            return "stable"
        case .dev:
            return "dev"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RuntimeUpdateApplyTrustIntent: Equatable, Sendable {
    case requireVerifiedPublisher
    case allowUnsignedDevelopmentBundle
}

public enum UpdateBundleKind: Codable, Equatable, Sendable {
    case productUpdate
    case vmImageUpdate
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "product-update":
            self = .productUpdate
        case "vm-image-update":
            self = .vmImageUpdate
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .productUpdate:
            return "product-update"
        case .vmImageUpdate:
            return "vm-image-update"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum UpdateBundleComponentKey: String, CaseIterable, Sendable {
    case helperUI
    case updater
    case supervisor
    case vmDriver
    case serviceStack
    case vmImage
    case vitalServer
}

public struct UpdateBundleArtifact: Codable, Equatable, Sendable {
    public let name: String
    public let type: UpdateBundleArtifactType
    public let sha256: String
    public let size: Int

    public init(name: String, type: UpdateBundleArtifactType, sha256: String, size: Int) {
        self.name = name
        self.type = type
        self.sha256 = sha256
        self.size = size
    }
}

public struct UpdateBundleMigration: Codable, Equatable, Sendable {
    public let name: String
    public let sha256: String
    public let size: Int

    public init(name: String, sha256: String, size: Int) {
        self.name = name
        self.sha256 = sha256
        self.size = size
    }
}

public struct UpdateBundleArtifactArchiveLayout: Equatable, Sendable {
    public let appBundleRoot: String
    public let nginxBundleRoot: String
    public let guestDeployRoot: String
    public let runtimeToolsAllowedRootEntries: Set<String>

    public init(
        appBundleRoot: String,
        nginxBundleRoot: String,
        guestDeployRoot: String,
        runtimeToolsAllowedRootEntries: Set<String>
    ) {
        self.appBundleRoot = appBundleRoot
        self.nginxBundleRoot = nginxBundleRoot
        self.guestDeployRoot = guestDeployRoot
        self.runtimeToolsAllowedRootEntries = runtimeToolsAllowedRootEntries
    }
}

public enum UpdateBundleArtifactArchiveLayouts {
    public static let vitalServerHelper = UpdateBundleArtifactArchiveLayout(
        appBundleRoot: "VitalServer Helper.app",
        nginxBundleRoot: "nginx",
        guestDeployRoot: "deploy",
        runtimeToolsAllowedRootEntries: [
            "vitalserver-vm",
            "vitalserver-proxy-run",
            "tirosh-vitalserver-uninstall",
        ]
    )
}

public enum UpdateBundleArtifactType: Codable, Equatable, Sendable {
    case rootfsBase
    case appBundle
    case nginxBundle
    case guestDeploy
    case runtimeTools
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "rootfs-base":
            self = .rootfsBase
        case "app-bundle":
            self = .appBundle
        case "nginx-bundle":
            self = .nginxBundle
        case "guest-deploy":
            self = .guestDeploy
        case "runtime-tools":
            self = .runtimeTools
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .rootfsBase:
            return "rootfs-base"
        case .appBundle:
            return "app-bundle"
        case .nginxBundle:
            return "nginx-bundle"
        case .guestDeploy:
            return "guest-deploy"
        case .runtimeTools:
            return "runtime-tools"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
