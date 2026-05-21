public struct UpdateBundleManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let product: String
    public let version: String
    public let runtimeVersion: String
    public let createdAt: String
    public let artifacts: [UpdateBundleArtifact]
    public let migrations: [UpdateBundleMigration]

    public init(
        schemaVersion: Int,
        product: String,
        version: String,
        runtimeVersion: String,
        createdAt: String,
        artifacts: [UpdateBundleArtifact],
        migrations: [UpdateBundleMigration]
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.version = version
        self.runtimeVersion = runtimeVersion
        self.createdAt = createdAt
        self.artifacts = artifacts
        self.migrations = migrations
    }
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
