import Foundation

public struct GuestRuntimeConfigDocument: Codable, Equatable, Sendable {
    public var vitalserverHttpPort: Int
    public var redisHost: String
    public var redisPort: Int
    public var trustProxy: Bool
    public var vitalServerURL: String
    public var remoteConsoleURL: String
    public var publicHost: String
    public var publicPort: Int
    public var adminPassword: String
    public var vitalFilesDirectory: String
    public var redisUiPort: Int
    public var swaggerUiPort: Int
    public var testkitEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case vitalserverHttpPort
        case redisHost
        case redisPort
        case trustProxy
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case adminPassword
        case vitalFilesDirectory
        case redisUiPort
        case swaggerUiPort
        case testkitEnabled
    }

    public init(
        vitalserverHttpPort: Int,
        redisHost: String,
        redisPort: Int,
        trustProxy: Bool,
        vitalServerURL: String = "",
        remoteConsoleURL: String = "",
        publicHost: String,
        publicPort: Int,
        adminPassword: String,
        vitalFilesDirectory: String,
        redisUiPort: Int,
        swaggerUiPort: Int,
        testkitEnabled: Bool
    ) {
        self.vitalserverHttpPort = vitalserverHttpPort
        self.redisHost = redisHost
        self.redisPort = redisPort
        self.trustProxy = trustProxy
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.adminPassword = adminPassword
        self.vitalFilesDirectory = vitalFilesDirectory
        self.redisUiPort = redisUiPort
        self.swaggerUiPort = swaggerUiPort
        self.testkitEnabled = testkitEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vitalserverHttpPort = try container.decode(Int.self, forKey: .vitalserverHttpPort)
        self.redisHost = try container.decode(String.self, forKey: .redisHost)
        self.redisPort = try container.decode(Int.self, forKey: .redisPort)
        self.trustProxy = try container.decode(Bool.self, forKey: .trustProxy)
        let publicHost = try container.decode(String.self, forKey: .publicHost)
        let publicPort = try container.decode(Int.self, forKey: .publicPort)
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.vitalServerURL = try container.decodeIfPresent(String.self, forKey: .vitalServerURL)
            ?? Self.legacyVitalServerURL(publicHost: publicHost, publicPort: publicPort)
        self.remoteConsoleURL = try container.decodeIfPresent(String.self, forKey: .remoteConsoleURL) ?? ""
        self.adminPassword = try container.decode(String.self, forKey: .adminPassword)
        self.vitalFilesDirectory = try container.decode(String.self, forKey: .vitalFilesDirectory)
        self.redisUiPort = try container.decode(Int.self, forKey: .redisUiPort)
        self.swaggerUiPort = try container.decode(Int.self, forKey: .swaggerUiPort)
        self.testkitEnabled = try container.decode(
            Bool.self,
            forKey: .testkitEnabled
        )
    }

    private static func legacyVitalServerURL(publicHost: String, publicPort: Int) -> String {
        "http://\(publicHost):\(publicPort)/"
    }
}

public struct GuestRuntimeSettingsDocument: Codable, Equatable, Sendable {
    public var vitalServerURL: String
    public var remoteConsoleURL: String
    public var publicHost: String
    public var publicPort: Int
    public var recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode
    public var recorderIngressSendDataReplayBatchSize: Int
    public var recorderIngressSendDataReplayMaxMiBPerSecond: Int
    public var containerMemoryLimitsEnabled: Bool
    public var vitalServerContainerMemoryLimitMiB: Int
    public var recorderIngressContainerMemoryLimitMiB: Int
    public var redisContainerMemoryLimitMiB: Int
    public var automaticBackupEnabled: Bool
    public var backupScheduleTimes: [String]
    public var backupRetentionCount: Int

    enum CodingKeys: String, CodingKey {
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case recorderIngressSendDataMode
        case recorderIngressSendDataReplayBatchSize
        case recorderIngressSendDataReplayMaxMiBPerSecond
        case containerMemoryLimitsEnabled
        case vitalServerContainerMemoryLimitMiB
        case recorderIngressContainerMemoryLimitMiB
        case redisContainerMemoryLimitMiB
        case automaticBackupEnabled
        case backupScheduleTimes
        case backupRetentionCount
    }

    public init(
        vitalServerURL: String,
        remoteConsoleURL: String,
        publicHost: String,
        publicPort: Int,
        recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode = RuntimeRecorderIngressDefaults.sendDataMode,
        recorderIngressSendDataReplayBatchSize: Int = RuntimeRecorderIngressDefaults.replayBatchSize,
        recorderIngressSendDataReplayMaxMiBPerSecond: Int = RuntimeRecorderIngressDefaults.replayMaxMiBPerSecond,
        containerMemoryLimitsEnabled: Bool = RuntimeContainerMemoryLimitDefaults.enabled,
        vitalServerContainerMemoryLimitMiB: Int = RuntimeContainerMemoryLimitDefaults.vitalServerMiB,
        recorderIngressContainerMemoryLimitMiB: Int = RuntimeContainerMemoryLimitDefaults.recorderIngressMiB,
        redisContainerMemoryLimitMiB: Int = RuntimeContainerMemoryLimitDefaults.redisMiB,
        automaticBackupEnabled: Bool = RuntimeSettingsInitialBackupDefaults.automaticBackupEnabled,
        backupScheduleTimes: [String] = RuntimeSettingsInitialBackupDefaults.backupScheduleTimes,
        backupRetentionCount: Int = RuntimeSettingsInitialBackupDefaults.backupRetentionCount
    ) {
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.recorderIngressSendDataMode = recorderIngressSendDataMode
        self.recorderIngressSendDataReplayBatchSize = recorderIngressSendDataReplayBatchSize
        self.recorderIngressSendDataReplayMaxMiBPerSecond = recorderIngressSendDataReplayMaxMiBPerSecond
        self.containerMemoryLimitsEnabled = containerMemoryLimitsEnabled
        self.vitalServerContainerMemoryLimitMiB = vitalServerContainerMemoryLimitMiB
        self.recorderIngressContainerMemoryLimitMiB = recorderIngressContainerMemoryLimitMiB
        self.redisContainerMemoryLimitMiB = redisContainerMemoryLimitMiB
        self.automaticBackupEnabled = automaticBackupEnabled
        self.backupScheduleTimes = backupScheduleTimes
        self.backupRetentionCount = backupRetentionCount
    }

    public init(runtimeConfig: GuestRuntimeConfigDocument) {
        self.init(
            vitalServerURL: runtimeConfig.vitalServerURL,
            remoteConsoleURL: runtimeConfig.remoteConsoleURL,
            publicHost: runtimeConfig.publicHost,
            publicPort: runtimeConfig.publicPort
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vitalServerURL: try container.decode(String.self, forKey: .vitalServerURL),
            remoteConsoleURL: try container.decode(String.self, forKey: .remoteConsoleURL),
            publicHost: try container.decode(String.self, forKey: .publicHost),
            publicPort: try container.decode(Int.self, forKey: .publicPort),
            recorderIngressSendDataMode: try container.decodeIfPresent(
                RuntimeRecorderIngressSendDataMode.self,
                forKey: .recorderIngressSendDataMode
            ) ?? RuntimeRecorderIngressDefaults.sendDataMode,
            recorderIngressSendDataReplayBatchSize: try container.decodeIfPresent(
                Int.self,
                forKey: .recorderIngressSendDataReplayBatchSize
            ) ?? RuntimeRecorderIngressDefaults.replayBatchSize,
            recorderIngressSendDataReplayMaxMiBPerSecond: try container.decodeIfPresent(
                Int.self,
                forKey: .recorderIngressSendDataReplayMaxMiBPerSecond
            ) ?? RuntimeRecorderIngressDefaults.replayMaxMiBPerSecond,
            containerMemoryLimitsEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .containerMemoryLimitsEnabled
            ) ?? RuntimeContainerMemoryLimitDefaults.enabled,
            vitalServerContainerMemoryLimitMiB: try container.decodeIfPresent(
                Int.self,
                forKey: .vitalServerContainerMemoryLimitMiB
            ) ?? RuntimeContainerMemoryLimitDefaults.vitalServerMiB,
            recorderIngressContainerMemoryLimitMiB: try container.decodeIfPresent(
                Int.self,
                forKey: .recorderIngressContainerMemoryLimitMiB
            ) ?? RuntimeContainerMemoryLimitDefaults.recorderIngressMiB,
            redisContainerMemoryLimitMiB: try container.decodeIfPresent(
                Int.self,
                forKey: .redisContainerMemoryLimitMiB
            ) ?? RuntimeContainerMemoryLimitDefaults.redisMiB,
            automaticBackupEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticBackupEnabled
            ) ?? RuntimeSettingsInitialBackupDefaults.automaticBackupEnabled,
            backupScheduleTimes: try container.decodeIfPresent(
                [String].self,
                forKey: .backupScheduleTimes
            ) ?? RuntimeSettingsInitialBackupDefaults.backupScheduleTimes,
            backupRetentionCount: try container.decodeIfPresent(
                Int.self,
                forKey: .backupRetentionCount
            ) ?? RuntimeSettingsInitialBackupDefaults.backupRetentionCount
        )
    }
}

public enum RuntimeRecorderIngressSendDataMode: String, Codable, CaseIterable, Equatable, Sendable {
    case passthrough
    case mirrorSpool = "mirror_spool"
    case spoolOnly = "spool_only"
    case spoolAndReplay = "spool_and_replay"
}

public enum RuntimeRecorderIngressDefaults {
    public static let sendDataMode = RuntimeRecorderIngressSendDataMode.spoolAndReplay
    public static let replayBatchSize = 1000
    public static let replayMaxMiBPerSecond = 20
}

public enum RuntimeContainerMemoryLimitDefaults {
    public static let enabled = true
    public static let vitalServerMiB = 2048
    public static let recorderIngressMiB = 410
    public static let redisMiB = 3277
}

public enum RuntimeSettingsInitialBackupDefaults {
    public static let automaticBackupEnabled = true
    public static let backupScheduleTimes = ["03:15"]
    public static let backupRetentionCount = 30
}
