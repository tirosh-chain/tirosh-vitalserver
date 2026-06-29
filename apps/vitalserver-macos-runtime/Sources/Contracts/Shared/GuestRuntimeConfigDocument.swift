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
    public var recorderIngress: RuntimeRecorderIngressSettings
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
        case recorderIngress
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
        recorderIngress: RuntimeRecorderIngressSettings = RuntimeRecorderIngressSettings(),
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
        self.recorderIngress = recorderIngress
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
            recorderIngress: try container.decodeIfPresent(
                RuntimeRecorderIngressSettings.self,
                forKey: .recorderIngress
            ) ?? RuntimeRecorderIngressSettings(),
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
    public static let sendDataMaxPendingItems = 100_000
    public static let sendDataMaxPendingMiB = 512
    public static let sendDataMaxPayloadMiB = 10
    public static let sendDataReplayedMaxItems = 10_000
    public static let sendDataRealtimeMaxPendingItems = 2_000
    public static let sendDataReplayIntervalMs = 1_000
    public static let sendDataReplayMaxAttempts = 3
    public static let sendDataReplayTargetTimeoutMs = 5_000
    public static let sendDataReplayAdaptiveMinConcurrency = 1
    public static let sendDataReplayAdaptiveMaxConcurrency = 8
    public static let rawArchiveEnabled = true
    public static let rawArchiveMaxFileMiB = 512
    public static let rawArchiveMaxFiles = 24
    public static let rawArchiveAutoExportEnabled = true
    public static let rawArchiveAutoExportQuietSeconds = 300
    public static let rawArchiveAutoExportScanIntervalSeconds = 60
    public static let rawArchiveAutoExportCursorStableSeconds = 60
    public static let rawArchiveAutoExportRetryDelaySeconds = 60
    public static let rawArchiveAutoExportMaxAttempts = 3
    public static let rawArchiveAutoExportRequestTimeoutSeconds = 300
}

public struct RuntimeRecorderIngressSettings: Codable, Equatable, Sendable {
    public var sendDataMaxPendingItems: Int
    public var sendDataMaxPendingMiB: Int
    public var sendDataMaxPayloadMiB: Int
    public var sendDataReplayedMaxItems: Int
    public var sendDataRealtimeMaxPendingItems: Int
    public var sendDataReplayIntervalMs: Int
    public var sendDataReplayMaxAttempts: Int
    public var sendDataReplayTargetTimeoutMs: Int
    public var sendDataReplayAdaptiveMinConcurrency: Int
    public var sendDataReplayAdaptiveMaxConcurrency: Int
    public var rawArchiveEnabled: Bool
    public var rawArchiveMaxFileMiB: Int
    public var rawArchiveMaxFiles: Int
    public var rawArchiveAutoExportEnabled: Bool
    public var rawArchiveAutoExportQuietSeconds: Int
    public var rawArchiveAutoExportScanIntervalSeconds: Int
    public var rawArchiveAutoExportCursorStableSeconds: Int
    public var rawArchiveAutoExportRetryDelaySeconds: Int
    public var rawArchiveAutoExportMaxAttempts: Int
    public var rawArchiveAutoExportRequestTimeoutSeconds: Int

    public init(
        sendDataMaxPendingItems: Int = RuntimeRecorderIngressDefaults.sendDataMaxPendingItems,
        sendDataMaxPendingMiB: Int = RuntimeRecorderIngressDefaults.sendDataMaxPendingMiB,
        sendDataMaxPayloadMiB: Int = RuntimeRecorderIngressDefaults.sendDataMaxPayloadMiB,
        sendDataReplayedMaxItems: Int = RuntimeRecorderIngressDefaults.sendDataReplayedMaxItems,
        sendDataRealtimeMaxPendingItems: Int = RuntimeRecorderIngressDefaults.sendDataRealtimeMaxPendingItems,
        sendDataReplayIntervalMs: Int = RuntimeRecorderIngressDefaults.sendDataReplayIntervalMs,
        sendDataReplayMaxAttempts: Int = RuntimeRecorderIngressDefaults.sendDataReplayMaxAttempts,
        sendDataReplayTargetTimeoutMs: Int = RuntimeRecorderIngressDefaults.sendDataReplayTargetTimeoutMs,
        sendDataReplayAdaptiveMinConcurrency: Int = RuntimeRecorderIngressDefaults.sendDataReplayAdaptiveMinConcurrency,
        sendDataReplayAdaptiveMaxConcurrency: Int = RuntimeRecorderIngressDefaults.sendDataReplayAdaptiveMaxConcurrency,
        rawArchiveEnabled: Bool = RuntimeRecorderIngressDefaults.rawArchiveEnabled,
        rawArchiveMaxFileMiB: Int = RuntimeRecorderIngressDefaults.rawArchiveMaxFileMiB,
        rawArchiveMaxFiles: Int = RuntimeRecorderIngressDefaults.rawArchiveMaxFiles,
        rawArchiveAutoExportEnabled: Bool = RuntimeRecorderIngressDefaults.rawArchiveAutoExportEnabled,
        rawArchiveAutoExportQuietSeconds: Int = RuntimeRecorderIngressDefaults.rawArchiveAutoExportQuietSeconds,
        rawArchiveAutoExportScanIntervalSeconds: Int = RuntimeRecorderIngressDefaults.rawArchiveAutoExportScanIntervalSeconds,
        rawArchiveAutoExportCursorStableSeconds: Int = RuntimeRecorderIngressDefaults.rawArchiveAutoExportCursorStableSeconds,
        rawArchiveAutoExportRetryDelaySeconds: Int = RuntimeRecorderIngressDefaults.rawArchiveAutoExportRetryDelaySeconds,
        rawArchiveAutoExportMaxAttempts: Int = RuntimeRecorderIngressDefaults.rawArchiveAutoExportMaxAttempts,
        rawArchiveAutoExportRequestTimeoutSeconds: Int = RuntimeRecorderIngressDefaults.rawArchiveAutoExportRequestTimeoutSeconds
    ) {
        self.sendDataMaxPendingItems = sendDataMaxPendingItems
        self.sendDataMaxPendingMiB = sendDataMaxPendingMiB
        self.sendDataMaxPayloadMiB = sendDataMaxPayloadMiB
        self.sendDataReplayedMaxItems = sendDataReplayedMaxItems
        self.sendDataRealtimeMaxPendingItems = sendDataRealtimeMaxPendingItems
        self.sendDataReplayIntervalMs = sendDataReplayIntervalMs
        self.sendDataReplayMaxAttempts = sendDataReplayMaxAttempts
        self.sendDataReplayTargetTimeoutMs = sendDataReplayTargetTimeoutMs
        self.sendDataReplayAdaptiveMinConcurrency = sendDataReplayAdaptiveMinConcurrency
        self.sendDataReplayAdaptiveMaxConcurrency = sendDataReplayAdaptiveMaxConcurrency
        self.rawArchiveEnabled = rawArchiveEnabled
        self.rawArchiveMaxFileMiB = rawArchiveMaxFileMiB
        self.rawArchiveMaxFiles = rawArchiveMaxFiles
        self.rawArchiveAutoExportEnabled = rawArchiveAutoExportEnabled
        self.rawArchiveAutoExportQuietSeconds = rawArchiveAutoExportQuietSeconds
        self.rawArchiveAutoExportScanIntervalSeconds = rawArchiveAutoExportScanIntervalSeconds
        self.rawArchiveAutoExportCursorStableSeconds = rawArchiveAutoExportCursorStableSeconds
        self.rawArchiveAutoExportRetryDelaySeconds = rawArchiveAutoExportRetryDelaySeconds
        self.rawArchiveAutoExportMaxAttempts = rawArchiveAutoExportMaxAttempts
        self.rawArchiveAutoExportRequestTimeoutSeconds = rawArchiveAutoExportRequestTimeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sendDataMaxPendingItems: try container.decodeIfPresent(Int.self, forKey: .sendDataMaxPendingItems)
                ?? RuntimeRecorderIngressDefaults.sendDataMaxPendingItems,
            sendDataMaxPendingMiB: try container.decodeIfPresent(Int.self, forKey: .sendDataMaxPendingMiB)
                ?? RuntimeRecorderIngressDefaults.sendDataMaxPendingMiB,
            sendDataMaxPayloadMiB: try container.decodeIfPresent(Int.self, forKey: .sendDataMaxPayloadMiB)
                ?? RuntimeRecorderIngressDefaults.sendDataMaxPayloadMiB,
            sendDataReplayedMaxItems: try container.decodeIfPresent(Int.self, forKey: .sendDataReplayedMaxItems)
                ?? RuntimeRecorderIngressDefaults.sendDataReplayedMaxItems,
            sendDataRealtimeMaxPendingItems: try container.decodeIfPresent(Int.self, forKey: .sendDataRealtimeMaxPendingItems)
                ?? RuntimeRecorderIngressDefaults.sendDataRealtimeMaxPendingItems,
            sendDataReplayIntervalMs: try container.decodeIfPresent(Int.self, forKey: .sendDataReplayIntervalMs)
                ?? RuntimeRecorderIngressDefaults.sendDataReplayIntervalMs,
            sendDataReplayMaxAttempts: try container.decodeIfPresent(Int.self, forKey: .sendDataReplayMaxAttempts)
                ?? RuntimeRecorderIngressDefaults.sendDataReplayMaxAttempts,
            sendDataReplayTargetTimeoutMs: try container.decodeIfPresent(Int.self, forKey: .sendDataReplayTargetTimeoutMs)
                ?? RuntimeRecorderIngressDefaults.sendDataReplayTargetTimeoutMs,
            sendDataReplayAdaptiveMinConcurrency: try container.decodeIfPresent(Int.self, forKey: .sendDataReplayAdaptiveMinConcurrency)
                ?? RuntimeRecorderIngressDefaults.sendDataReplayAdaptiveMinConcurrency,
            sendDataReplayAdaptiveMaxConcurrency: try container.decodeIfPresent(Int.self, forKey: .sendDataReplayAdaptiveMaxConcurrency)
                ?? RuntimeRecorderIngressDefaults.sendDataReplayAdaptiveMaxConcurrency,
            rawArchiveEnabled: try container.decodeIfPresent(Bool.self, forKey: .rawArchiveEnabled)
                ?? RuntimeRecorderIngressDefaults.rawArchiveEnabled,
            rawArchiveMaxFileMiB: try container.decodeIfPresent(Int.self, forKey: .rawArchiveMaxFileMiB)
                ?? RuntimeRecorderIngressDefaults.rawArchiveMaxFileMiB,
            rawArchiveMaxFiles: try container.decodeIfPresent(Int.self, forKey: .rawArchiveMaxFiles)
                ?? RuntimeRecorderIngressDefaults.rawArchiveMaxFiles,
            rawArchiveAutoExportEnabled: try container.decodeIfPresent(Bool.self, forKey: .rawArchiveAutoExportEnabled)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportEnabled,
            rawArchiveAutoExportQuietSeconds: try container.decodeIfPresent(Int.self, forKey: .rawArchiveAutoExportQuietSeconds)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportQuietSeconds,
            rawArchiveAutoExportScanIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .rawArchiveAutoExportScanIntervalSeconds)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportScanIntervalSeconds,
            rawArchiveAutoExportCursorStableSeconds: try container.decodeIfPresent(Int.self, forKey: .rawArchiveAutoExportCursorStableSeconds)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportCursorStableSeconds,
            rawArchiveAutoExportRetryDelaySeconds: try container.decodeIfPresent(Int.self, forKey: .rawArchiveAutoExportRetryDelaySeconds)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportRetryDelaySeconds,
            rawArchiveAutoExportMaxAttempts: try container.decodeIfPresent(Int.self, forKey: .rawArchiveAutoExportMaxAttempts)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportMaxAttempts,
            rawArchiveAutoExportRequestTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .rawArchiveAutoExportRequestTimeoutSeconds)
                ?? RuntimeRecorderIngressDefaults.rawArchiveAutoExportRequestTimeoutSeconds
        )
    }
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
