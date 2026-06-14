import Foundation

public enum RuntimeDataBackupKind: String, Codable, Equatable, Sendable {
    case runtimeData = "runtime-data"
}

public enum RuntimeDataBackupCompatibility {
    public static let currentDataCompatibilityVersion = 1
}

public enum RuntimeDataBackupArtifactID: String, Codable, CaseIterable, Equatable, Sendable {
    case redisData = "redis-data"
    case runtimeVMConfig = "runtime-vm-config"
    case guestRuntimeConfig = "guest-runtime-config"
    case guestRuntimeSettings = "guest-runtime-settings"
    case proxyLaunchDaemonSettings = "proxy-launch-daemon-settings"
    case startOnBootState = "start-on-boot-state"
    case runtimeStatusDocument = "runtime-status-document"
    case runtimeEventsDocument = "runtime-events-document"
    case runtimeObservabilityDatabase = "runtime-observability-database"

    public static let requiredForUIContinuity: [RuntimeDataBackupArtifactID] = [
        .redisData,
        .runtimeVMConfig,
        .guestRuntimeConfig,
        .guestRuntimeSettings,
        .proxyLaunchDaemonSettings,
        .startOnBootState,
        .runtimeStatusDocument,
        .runtimeEventsDocument,
        .runtimeObservabilityDatabase,
    ]

    public static let requiredForRecovery: [RuntimeDataBackupArtifactID] = [
        .redisData,
        .runtimeVMConfig,
        .guestRuntimeConfig,
        .guestRuntimeSettings,
        .proxyLaunchDaemonSettings,
        .startOnBootState,
    ]

    public static let optionalForUIContinuity: [RuntimeDataBackupArtifactID] = [
        .runtimeStatusDocument,
        .runtimeEventsDocument,
        .runtimeObservabilityDatabase,
    ]

    public var defaultBackupName: String {
        switch self {
        case .redisData:
            return "redis-data.tar.gz"
        case .runtimeVMConfig:
            return "runtime-vm-config.json"
        case .guestRuntimeConfig:
            return "guest-runtime-config.json"
        case .guestRuntimeSettings:
            return "guest-runtime-settings.json"
        case .proxyLaunchDaemonSettings:
            return "proxy-launch-daemon-settings.plist"
        case .startOnBootState:
            return "start-on-boot-state.json"
        case .runtimeStatusDocument:
            return RuntimeFileNames.runtimeStatus
        case .runtimeEventsDocument:
            return RuntimeFileNames.runtimeEvents
        case .runtimeObservabilityDatabase:
            return RuntimeFileNames.runtimeObservabilityDB
        }
    }
}

public enum RuntimeDataBackupArtifactRole: String, Codable, Equatable, Sendable {
    case required
    case optional
}

public enum RuntimeDataBackupArtifactOwner: String, Codable, Equatable, Sendable {
    case host
    case guest
}

public enum RuntimeDataBackupSourceKind: String, Codable, Equatable, Sendable {
    case file
    case sqliteSnapshot = "sqlite-snapshot"
    case dockerVolumeArchive = "docker-volume-archive"
    case generatedState = "generated-state"
}

public enum RuntimeDataBackupArtifactState: String, Codable, Equatable, Sendable {
    case archived
    case missing
    case readFailed = "read-failed"
    case writeFailed = "write-failed"
    case skipped
}

public struct RuntimeDataBackupArtifact: Codable, Equatable, Sendable {
    public let id: RuntimeDataBackupArtifactID
    public let role: RuntimeDataBackupArtifactRole
    public let owner: RuntimeDataBackupArtifactOwner
    public let sourceKind: RuntimeDataBackupSourceKind
    public let sourcePath: String?
    public let volumeName: String?
    public let backupPath: String?
    public let state: RuntimeDataBackupArtifactState
    public let sizeBytes: UInt64?
    public let sha256: String?
    public let error: String?

    public init(
        id: RuntimeDataBackupArtifactID,
        role: RuntimeDataBackupArtifactRole = .required,
        owner: RuntimeDataBackupArtifactOwner,
        sourceKind: RuntimeDataBackupSourceKind,
        sourcePath: String? = nil,
        volumeName: String? = nil,
        backupPath: String? = nil,
        state: RuntimeDataBackupArtifactState,
        sizeBytes: UInt64? = nil,
        sha256: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.role = role
        self.owner = owner
        self.sourceKind = sourceKind
        self.sourcePath = sourcePath
        self.volumeName = volumeName
        self.backupPath = backupPath
        self.state = state
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.error = error
    }
}

public struct RuntimeDataBackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let dataCompatibilityVersion: Int?
    public let backupKind: RuntimeDataBackupKind
    public let product: String
    public let createdAt: String
    public let reason: String
    public let runtimeVersion: String?
    public let sourceRuntimeHome: String
    public let artifacts: [RuntimeDataBackupArtifact]

    public init(
        schemaVersion: Int = 1,
        dataCompatibilityVersion: Int? = RuntimeDataBackupCompatibility.currentDataCompatibilityVersion,
        backupKind: RuntimeDataBackupKind = .runtimeData,
        product: String,
        createdAt: String,
        reason: String,
        runtimeVersion: String? = nil,
        sourceRuntimeHome: String,
        artifacts: [RuntimeDataBackupArtifact]
    ) {
        self.schemaVersion = schemaVersion
        self.dataCompatibilityVersion = dataCompatibilityVersion
        self.backupKind = backupKind
        self.product = product
        self.createdAt = createdAt
        self.reason = reason
        self.runtimeVersion = runtimeVersion
        self.sourceRuntimeHome = sourceRuntimeHome
        self.artifacts = artifacts
    }
}

public struct RuntimeDataBackupStartOnBootStateDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let capturedAt: String
    public let services: [RuntimeDataBackupStartOnBootServiceState]

    public init(
        schemaVersion: Int,
        capturedAt: String,
        services: [RuntimeDataBackupStartOnBootServiceState]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.services = services
    }
}

public struct RuntimeDataBackupStartOnBootServiceState: Codable, Equatable, Sendable {
    public let label: String
    public let disabled: Bool

    public init(label: String, disabled: Bool) {
        self.label = label
        self.disabled = disabled
    }
}
