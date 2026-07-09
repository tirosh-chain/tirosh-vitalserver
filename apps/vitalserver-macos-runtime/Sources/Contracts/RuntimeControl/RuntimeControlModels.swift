import Foundation
import Contracts
import Errors

public struct RuntimeControlCapabilities: Codable, Equatable, Sendable {
    public var canInstallRuntime: Bool
    public var canUninstallRuntime: Bool
    public var canApplyBundle: Bool
    public var canRollback: Bool
    public var canEditVMResources: Bool
    public var canEditNetworkExposure: Bool
    public var canResetAdminPassword: Bool
    public var canOpenLocalFiles: Bool
    public var canStreamLogs: Bool
    public var canControlRuntimeServices: Bool
    public var canControlGuestServices: Bool
    public var canExportLogs: Bool
    public var canViewReleaseMetadata: Bool
    public var canUseLab: Bool

    public init(
        canInstallRuntime: Bool = true,
        canUninstallRuntime: Bool = true,
        canApplyBundle: Bool = true,
        canRollback: Bool = true,
        canEditVMResources: Bool = true,
        canEditNetworkExposure: Bool = true,
        canResetAdminPassword: Bool = true,
        canOpenLocalFiles: Bool = true,
        canStreamLogs: Bool = true,
        canControlRuntimeServices: Bool = true,
        canControlGuestServices: Bool = true,
        canExportLogs: Bool = true,
        canViewReleaseMetadata: Bool = true,
        canUseLab: Bool = true
    ) {
        self.canInstallRuntime = canInstallRuntime
        self.canUninstallRuntime = canUninstallRuntime
        self.canApplyBundle = canApplyBundle
        self.canRollback = canRollback
        self.canEditVMResources = canEditVMResources
        self.canEditNetworkExposure = canEditNetworkExposure
        self.canResetAdminPassword = canResetAdminPassword
        self.canOpenLocalFiles = canOpenLocalFiles
        self.canStreamLogs = canStreamLogs
        self.canControlRuntimeServices = canControlRuntimeServices
        self.canControlGuestServices = canControlGuestServices
        self.canExportLogs = canExportLogs
        self.canViewReleaseMetadata = canViewReleaseMetadata
        self.canUseLab = canUseLab
    }
}

public struct RuntimeContainerMemoryUsage: Codable, Equatable, Sendable {
    public var usedBytes: Int64
    public var limitBytes: Int64?

    public init(usedBytes: Int64, limitBytes: Int64? = nil) {
        self.usedBytes = usedBytes
        self.limitBytes = limitBytes
    }

    public var percent: Double? {
        guard let limitBytes, limitBytes > 0 else {
            return nil
        }
        return min(max((Double(usedBytes) / Double(limitBytes)) * 100.0, 0), 100)
    }
}

public enum RuntimeNetworkMode: String, Codable, Equatable, Sendable {
    case shared
    case bridged
}

public enum RuntimeState: Codable, Equatable, Sendable {
    case installing
    case initializing
    case updating
    case recovering
    case healthy
    case degraded
    case critical
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "installing":
            self = .installing
        case "initializing":
            self = .initializing
        case "updating":
            self = .updating
        case "recovering":
            self = .recovering
        case "healthy":
            self = .healthy
        case "degraded":
            self = .degraded
        case "critical":
            self = .critical
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .installing:
            return "installing"
        case .initializing:
            return "initializing"
        case .updating:
            return "updating"
        case .recovering:
            return "recovering"
        case .healthy:
            return "healthy"
        case .degraded:
            return "degraded"
        case .critical:
            return "critical"
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

public struct RuntimeSettings: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case readIssues
        case cpuCount
        case memoryGiB
        case diskGiB
        case minimumDiskGiB
        case networkMode
        case bridgedInterface
        case proxyPort
        case runtimeControlPort
        case vitalFilesDirectory
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
        case adminPassword
        case changeAdminPassword
        case startOnBoot
        case startOnBootConfigurable
        case autoRecoveryEnabled
        case preventSystemSleep
        case automaticBackupEnabled
        case backupScheduleTimes
        case backupRetentionCount
        case logArchiveRetentionDays
        case logArchiveMaximumGiB
        case redisRelay
        case restartAfterSave
        case appliedVMSettings
    }

    public var readIssues: [RuntimeSettingsReadIssue]
    public var cpuCount: Int
    public var memoryGiB: Int
    public var diskGiB: Int
    public var minimumDiskGiB: Int
    public var networkMode: RuntimeNetworkMode
    public var bridgedInterface: String?
    public var proxyPort: Int
    public var runtimeControlPort: Int
    public var vitalFilesDirectory: String
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
    public var adminPassword: String
    public var changeAdminPassword: Bool
    public var startOnBoot: Bool
    public var startOnBootConfigurable: Bool
    public var autoRecoveryEnabled: Bool
    public var preventSystemSleep: Bool
    public var automaticBackupEnabled: Bool
    public var backupScheduleTimes: [String]
    public var backupRetentionCount: Int
    public var logArchiveRetentionDays: Int
    public var logArchiveMaximumGiB: Int
    public var redisRelay: RuntimeRedisRelaySettings
    public var restartAfterSave: Bool
    public var appliedVMSettings: RuntimeAppliedVMSettings?

    public init(
        readIssues: [RuntimeSettingsReadIssue] = [],
        cpuCount: Int = RuntimeSettingsInitialValues.cpuCount,
        memoryGiB: Int = RuntimeSettingsInitialValues.memoryGiB,
        diskGiB: Int = RuntimeSettingsInitialValues.diskGiB,
        minimumDiskGiB: Int = RuntimeSettingsInitialValues.minimumDiskGiB,
        networkMode: RuntimeNetworkMode = .shared,
        bridgedInterface: String? = nil,
        proxyPort: Int = RuntimeSettingsInitialValues.proxyPort,
        runtimeControlPort: Int = RuntimeSettingsInitialValues.runtimeControlPort,
        vitalFilesDirectory: String = RuntimeSettingsInitialValues.vitalFilesDirectory,
        vitalServerURL: String = RuntimeSettingsInitialValues.vitalServerURL(),
        remoteConsoleURL: String = RuntimeSettingsInitialValues.remoteConsoleURL(),
        publicHost: String = "",
        publicPort: Int = RuntimeSettingsInitialValues.proxyPort,
        recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode = RuntimeSettingsInitialValues.recorderIngressSendDataMode,
        recorderIngressSendDataReplayBatchSize: Int = RuntimeSettingsInitialValues.recorderIngressSendDataReplayBatchSize,
        recorderIngressSendDataReplayMaxMiBPerSecond: Int = RuntimeSettingsInitialValues.recorderIngressSendDataReplayMaxMiBPerSecond,
        recorderIngress: RuntimeRecorderIngressSettings = RuntimeRecorderIngressSettings(),
        containerMemoryLimitsEnabled: Bool = RuntimeSettingsInitialValues.containerMemoryLimitsEnabled,
        vitalServerContainerMemoryLimitMiB: Int = RuntimeSettingsInitialValues.vitalServerContainerMemoryLimitMiB,
        recorderIngressContainerMemoryLimitMiB: Int = RuntimeSettingsInitialValues.recorderIngressContainerMemoryLimitMiB,
        redisContainerMemoryLimitMiB: Int = RuntimeSettingsInitialValues.redisContainerMemoryLimitMiB,
        adminPassword: String = "",
        changeAdminPassword: Bool = false,
        startOnBoot: Bool = true,
        startOnBootConfigurable: Bool = true,
        autoRecoveryEnabled: Bool = true,
        preventSystemSleep: Bool = true,
        automaticBackupEnabled: Bool = RuntimeSettingsInitialValues.automaticBackupEnabled,
        backupScheduleTimes: [String] = RuntimeSettingsInitialValues.backupScheduleTimes,
        backupRetentionCount: Int = RuntimeSettingsInitialValues.backupRetentionCount,
        logArchiveRetentionDays: Int = RuntimeSettingsInitialValues.logArchiveRetentionDays,
        logArchiveMaximumGiB: Int = RuntimeSettingsInitialValues.logArchiveMaximumGiB,
        redisRelay: RuntimeRedisRelaySettings = RuntimeRedisRelaySettings(),
        restartAfterSave: Bool = false,
        appliedVMSettings: RuntimeAppliedVMSettings? = nil
    ) {
        self.readIssues = readIssues
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
        self.minimumDiskGiB = minimumDiskGiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.proxyPort = proxyPort
        self.runtimeControlPort = runtimeControlPort
        self.vitalFilesDirectory = vitalFilesDirectory
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.recorderIngressSendDataMode = recorderIngressSendDataMode
        self.recorderIngressSendDataReplayBatchSize = max(
            recorderIngressSendDataReplayBatchSize,
            RuntimeSettingsInitialValues.recorderIngressSendDataReplayBatchSize
        )
        self.recorderIngressSendDataReplayMaxMiBPerSecond = recorderIngressSendDataReplayMaxMiBPerSecond
        self.recorderIngress = recorderIngress
        self.containerMemoryLimitsEnabled = containerMemoryLimitsEnabled
        self.vitalServerContainerMemoryLimitMiB = vitalServerContainerMemoryLimitMiB
        self.recorderIngressContainerMemoryLimitMiB = recorderIngressContainerMemoryLimitMiB
        self.redisContainerMemoryLimitMiB = redisContainerMemoryLimitMiB
        self.adminPassword = adminPassword
        self.changeAdminPassword = changeAdminPassword
        self.startOnBoot = startOnBoot
        self.startOnBootConfigurable = startOnBootConfigurable
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
        self.automaticBackupEnabled = automaticBackupEnabled
        self.backupScheduleTimes = backupScheduleTimes
        self.backupRetentionCount = backupRetentionCount
        self.logArchiveRetentionDays = logArchiveRetentionDays
        self.logArchiveMaximumGiB = logArchiveMaximumGiB
        self.redisRelay = redisRelay
        self.restartAfterSave = restartAfterSave
        self.appliedVMSettings = appliedVMSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.bridgedInterface) else {
            throw DecodingError.keyNotFound(
                CodingKeys.bridgedInterface,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "RuntimeSettings.bridgedInterface is required and may be null only when no bridged interface is configured"
                )
            )
        }
        let bridgedInterface: String?
        if try container.decodeNil(forKey: .bridgedInterface) {
            bridgedInterface = nil
        } else {
            bridgedInterface = try container.decode(String.self, forKey: .bridgedInterface)
        }

        self.init(
            readIssues: try container.decode([RuntimeSettingsReadIssue].self, forKey: .readIssues),
            cpuCount: try container.decode(Int.self, forKey: .cpuCount),
            memoryGiB: try container.decode(Int.self, forKey: .memoryGiB),
            diskGiB: try container.decode(Int.self, forKey: .diskGiB),
            minimumDiskGiB: try container.decode(Int.self, forKey: .minimumDiskGiB),
            networkMode: try container.decode(RuntimeNetworkMode.self, forKey: .networkMode),
            bridgedInterface: bridgedInterface,
            proxyPort: try container.decode(Int.self, forKey: .proxyPort),
            runtimeControlPort: try container.decode(Int.self, forKey: .runtimeControlPort),
            vitalFilesDirectory: try container.decode(String.self, forKey: .vitalFilesDirectory),
            vitalServerURL: try container.decode(String.self, forKey: .vitalServerURL),
            remoteConsoleURL: try container.decode(String.self, forKey: .remoteConsoleURL),
            publicHost: try container.decode(String.self, forKey: .publicHost),
            publicPort: try container.decode(Int.self, forKey: .publicPort),
            recorderIngressSendDataMode: try container.decodeIfPresent(
                RuntimeRecorderIngressSendDataMode.self,
                forKey: .recorderIngressSendDataMode
            ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataMode,
            recorderIngressSendDataReplayBatchSize: try container.decodeIfPresent(
                Int.self,
                forKey: .recorderIngressSendDataReplayBatchSize
            ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataReplayBatchSize,
            recorderIngressSendDataReplayMaxMiBPerSecond: try container.decodeIfPresent(
                Int.self,
                forKey: .recorderIngressSendDataReplayMaxMiBPerSecond
            ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataReplayMaxMiBPerSecond,
            recorderIngress: try container.decodeIfPresent(
                RuntimeRecorderIngressSettings.self,
                forKey: .recorderIngress
            ) ?? RuntimeRecorderIngressSettings(),
            containerMemoryLimitsEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .containerMemoryLimitsEnabled
            ) ?? RuntimeSettingsInitialValues.containerMemoryLimitsEnabled,
            vitalServerContainerMemoryLimitMiB: try container.decodeIfPresent(
                Int.self,
                forKey: .vitalServerContainerMemoryLimitMiB
            ) ?? RuntimeSettingsInitialValues.vitalServerContainerMemoryLimitMiB,
            recorderIngressContainerMemoryLimitMiB: try container.decodeIfPresent(
                Int.self,
                forKey: .recorderIngressContainerMemoryLimitMiB
            ) ?? RuntimeSettingsInitialValues.recorderIngressContainerMemoryLimitMiB,
            redisContainerMemoryLimitMiB: try container.decodeIfPresent(
                Int.self,
                forKey: .redisContainerMemoryLimitMiB
            ) ?? RuntimeSettingsInitialValues.redisContainerMemoryLimitMiB,
            adminPassword: try container.decode(String.self, forKey: .adminPassword),
            changeAdminPassword: try container.decode(Bool.self, forKey: .changeAdminPassword),
            startOnBoot: try container.decode(Bool.self, forKey: .startOnBoot),
            startOnBootConfigurable: try container.decode(Bool.self, forKey: .startOnBootConfigurable),
            autoRecoveryEnabled: try container.decode(Bool.self, forKey: .autoRecoveryEnabled),
            preventSystemSleep: try container.decode(Bool.self, forKey: .preventSystemSleep),
            automaticBackupEnabled: try container.decode(Bool.self, forKey: .automaticBackupEnabled),
            backupScheduleTimes: try container.decode([String].self, forKey: .backupScheduleTimes),
            backupRetentionCount: try container.decode(Int.self, forKey: .backupRetentionCount),
            logArchiveRetentionDays: try container.decode(Int.self, forKey: .logArchiveRetentionDays),
            logArchiveMaximumGiB: try container.decode(Int.self, forKey: .logArchiveMaximumGiB),
            redisRelay: try container.decodeIfPresent(RuntimeRedisRelaySettings.self, forKey: .redisRelay) ?? RuntimeRedisRelaySettings(),
            restartAfterSave: try container.decode(Bool.self, forKey: .restartAfterSave),
            appliedVMSettings: try container.decodeIfPresent(RuntimeAppliedVMSettings.self, forKey: .appliedVMSettings)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readIssues, forKey: .readIssues)
        try container.encode(cpuCount, forKey: .cpuCount)
        try container.encode(memoryGiB, forKey: .memoryGiB)
        try container.encode(diskGiB, forKey: .diskGiB)
        try container.encode(minimumDiskGiB, forKey: .minimumDiskGiB)
        try container.encode(networkMode, forKey: .networkMode)
        if let bridgedInterface {
            try container.encode(bridgedInterface, forKey: .bridgedInterface)
        } else {
            try container.encodeNil(forKey: .bridgedInterface)
        }
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(runtimeControlPort, forKey: .runtimeControlPort)
        try container.encode(vitalFilesDirectory, forKey: .vitalFilesDirectory)
        try container.encode(vitalServerURL, forKey: .vitalServerURL)
        try container.encode(remoteConsoleURL, forKey: .remoteConsoleURL)
        try container.encode(publicHost, forKey: .publicHost)
        try container.encode(publicPort, forKey: .publicPort)
        try container.encode(recorderIngressSendDataMode, forKey: .recorderIngressSendDataMode)
        try container.encode(recorderIngressSendDataReplayBatchSize, forKey: .recorderIngressSendDataReplayBatchSize)
        try container.encode(
            recorderIngressSendDataReplayMaxMiBPerSecond,
            forKey: .recorderIngressSendDataReplayMaxMiBPerSecond
        )
        try container.encode(recorderIngress, forKey: .recorderIngress)
        try container.encode(containerMemoryLimitsEnabled, forKey: .containerMemoryLimitsEnabled)
        try container.encode(vitalServerContainerMemoryLimitMiB, forKey: .vitalServerContainerMemoryLimitMiB)
        try container.encode(recorderIngressContainerMemoryLimitMiB, forKey: .recorderIngressContainerMemoryLimitMiB)
        try container.encode(redisContainerMemoryLimitMiB, forKey: .redisContainerMemoryLimitMiB)
        try container.encode(adminPassword, forKey: .adminPassword)
        try container.encode(changeAdminPassword, forKey: .changeAdminPassword)
        try container.encode(startOnBoot, forKey: .startOnBoot)
        try container.encode(startOnBootConfigurable, forKey: .startOnBootConfigurable)
        try container.encode(autoRecoveryEnabled, forKey: .autoRecoveryEnabled)
        try container.encode(preventSystemSleep, forKey: .preventSystemSleep)
        try container.encode(automaticBackupEnabled, forKey: .automaticBackupEnabled)
        try container.encode(backupScheduleTimes, forKey: .backupScheduleTimes)
        try container.encode(backupRetentionCount, forKey: .backupRetentionCount)
        try container.encode(logArchiveRetentionDays, forKey: .logArchiveRetentionDays)
        try container.encode(logArchiveMaximumGiB, forKey: .logArchiveMaximumGiB)
        try container.encode(redisRelay, forKey: .redisRelay)
        try container.encode(restartAfterSave, forKey: .restartAfterSave)
        try container.encodeIfPresent(appliedVMSettings, forKey: .appliedVMSettings)
    }
}

public enum RuntimeRedisRelayScope: String, Codable, CaseIterable, Sendable {
    case waveformTrendOnly = "waveform_trend_only"
    case vitalReconstruction = "vital_reconstruction"
}

public struct RuntimeRedisRelayTarget: Codable, Equatable, Sendable {
    public static let defaultURL = "redis://redis.example:6379/0"

    public var url: String
    public var username: String
    public var password: String
    public var clearPassword: Bool
    public var passwordConfigured: Bool
    public var tls: Bool

    public init(
        url: String = RuntimeRedisRelayTarget.defaultURL,
        username: String = "",
        password: String = "",
        clearPassword: Bool = false,
        passwordConfigured: Bool = false,
        tls: Bool = false
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.clearPassword = clearPassword
        self.passwordConfigured = passwordConfigured
        self.tls = tls
    }

    enum CodingKeys: String, CodingKey {
        case url
        case username
        case password
        case clearPassword
        case passwordConfigured
        case tls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            url: try container.decodeIfPresent(String.self, forKey: .url) ?? Self.defaultURL,
            username: try container.decodeIfPresent(String.self, forKey: .username) ?? "",
            password: try container.decodeIfPresent(String.self, forKey: .password) ?? "",
            clearPassword: try container.decodeIfPresent(Bool.self, forKey: .clearPassword) ?? false,
            passwordConfigured: try container.decodeIfPresent(Bool.self, forKey: .passwordConfigured) ?? false,
            tls: try container.decodeIfPresent(Bool.self, forKey: .tls) ?? false
        )
    }
}

public struct RuntimeRedisRelaySettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var target: RuntimeRedisRelayTarget
    public var scope: RuntimeRedisRelayScope
    public var includeRecorderNetworkContext: Bool
    public var intervalSeconds: Double
    public var scanCount: Int

    public init(
        enabled: Bool = false,
        target: RuntimeRedisRelayTarget = RuntimeRedisRelayTarget(),
        scope: RuntimeRedisRelayScope = .vitalReconstruction,
        includeRecorderNetworkContext: Bool = false,
        intervalSeconds: Double = 1.0,
        scanCount: Int = 1000
    ) {
        self.enabled = enabled
        self.target = target
        self.scope = scope
        self.includeRecorderNetworkContext = includeRecorderNetworkContext
        self.intervalSeconds = intervalSeconds
        self.scanCount = scanCount
    }
}

public struct RuntimeAppliedVMSettings: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memoryGiB: Int
    public let networkMode: RuntimeNetworkMode
    public let bridgedInterface: String?
    public let vitalFilesDirectory: String

    public init(
        cpuCount: Int,
        memoryGiB: Int,
        networkMode: RuntimeNetworkMode,
        bridgedInterface: String?,
        vitalFilesDirectory: String
    ) {
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.vitalFilesDirectory = vitalFilesDirectory
    }
}

public extension RuntimeSettings {
    var runtimeAppliedSettings: RuntimeSettings {
        guard let appliedVMSettings else {
            return self
        }
        var runtime = self
        runtime.cpuCount = appliedVMSettings.cpuCount
        runtime.memoryGiB = appliedVMSettings.memoryGiB
        runtime.networkMode = appliedVMSettings.networkMode
        runtime.bridgedInterface = appliedVMSettings.bridgedInterface
        runtime.vitalFilesDirectory = appliedVMSettings.vitalFilesDirectory
        runtime.appliedVMSettings = appliedVMSettings
        return runtime
    }
}

public enum RuntimeSettingsInitialValues {
    public static let localhost = "127.0.0.1"
    public static let cpuCount = 8
    public static let memoryGiB = 8
    public static let diskGiB = 32
    public static let minimumDiskGiB = 4
    public static let proxyPort = 80
    public static let runtimeControlPort = 18_321
    public static let vitalFilesDirectory = "/Users/Shared/VitalServerHelper/vital-files"
    public static let automaticBackupEnabled = RuntimeSettingsInitialBackupDefaults.automaticBackupEnabled
    public static let backupScheduleTimes = RuntimeSettingsInitialBackupDefaults.backupScheduleTimes
    public static let backupRetentionCount = RuntimeSettingsInitialBackupDefaults.backupRetentionCount
    public static let logArchiveRetentionDays = RuntimeLogArchiveRetentionConfiguration.defaultRetentionDays
    public static let logArchiveMaximumGiB = Int(RuntimeLogArchiveRetentionConfiguration.defaultMaximumBytes / 1_073_741_824)
    public static let recorderIngressSendDataMode = RuntimeRecorderIngressDefaults.sendDataMode
    public static let recorderIngressSendDataReplayBatchSize = RuntimeRecorderIngressDefaults.replayBatchSize
    public static let recorderIngressSendDataReplayMaxMiBPerSecond = RuntimeRecorderIngressDefaults.replayMaxMiBPerSecond
    public static let containerMemoryLimitsEnabled = RuntimeContainerMemoryLimitDefaults.enabled
    public static let vitalServerContainerMemoryLimitMiB = RuntimeContainerMemoryLimitDefaults.vitalServerMiB
    public static let recorderIngressContainerMemoryLimitMiB = RuntimeContainerMemoryLimitDefaults.recorderIngressMiB
    public static let redisContainerMemoryLimitMiB = RuntimeContainerMemoryLimitDefaults.redisMiB

    public static func vitalServerURL(proxyPort: Int = proxyPort) -> String {
        "http://\(localhost):\(proxyPort)/"
    }

    public static func remoteConsoleURL(runtimeControlPort: Int = runtimeControlPort) -> String {
        "http://\(localhost):\(runtimeControlPort)/"
    }

    public static func isInitialVitalServerURL(_ value: String) -> Bool {
        isInitialLocalhostURL(value)
    }

    public static func isInitialRemoteConsoleURL(_ value: String) -> Bool {
        isInitialLocalhostURL(value)
    }

    private static func isInitialLocalhostURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "http",
              url.host == localhost,
              url.path == "/" || url.path.isEmpty,
              url.query == nil,
              url.fragment == nil else {
            return false
        }
        return url.port != nil
    }
}

public enum RuntimeControlLocalAPIConnectionDefaults {
    public static let headerName = "X-Runtime-Control-Token"
    public static let token = "vitalserver-helper-dev"

    public static func baseURL(
        runtimeControlPort: Int = RuntimeSettingsInitialValues.runtimeControlPort
    ) -> String {
        RuntimeSettingsInitialValues.remoteConsoleURL(runtimeControlPort: runtimeControlPort)
    }
}

public struct RuntimeSettingsReadIssue: Codable, Equatable, Sendable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public struct RuntimeDataDirectoryStats: Codable, Equatable, Sendable {
    public let fileCount: Int
    public let sizeBytes: Int64

    public init(fileCount: Int, sizeBytes: Int64) {
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
    }
}

public struct RuntimeStatusReadIssue: Codable, Equatable, Sendable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public enum RuntimeServiceStateSource: String, Codable, Equatable, Sendable {
    case liveLaunchd = "live-launchd"
}

public enum RuntimeGuestServicesReadState: String, Codable, Equatable, Sendable {
    case unavailable
    case loaded
    case failed
}

public struct RuntimeStatus: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case runtimeInstalled
        case runtimeInstallationState
        case vmServiceLoaded
        case proxyServiceLoaded
        case guestLogSyncServiceLoaded
        case sleepPreventionServiceLoaded
        case watchdogServiceLoaded
        case vmServiceState
        case proxyServiceState
        case guestLogSyncServiceState
        case sleepPreventionServiceState
        case watchdogServiceState
        case vmServiceStateSource
        case proxyServiceStateSource
        case guestLogSyncServiceStateSource
        case sleepPreventionServiceStateSource
        case watchdogServiceStateSource
        case runtimeState
        case readIssues
        case runtimeVersion
        case latestBackup
        case vmState
        case vmErrors
        case vmIP
        case guestHTTP
        case hostProxyHTTP
        case runtimeControlHTTP
        case runtimeControlStartedAt
        case redisUIHTTP
        case swaggerUIHTTP
        case guestServicesReadState
        case guestServices
        case guestServiceStatuses
        case guestServiceResources
        case guestServiceResourceReadIssues
        case guestStackProbeErrors
        case guestServicesReadError
        case cpuUsagePercent
        case memory
        case vitalServerMemory
        case recorderIngressMemory
        case redisMemory
        case systemDisk
        case dataStorage
        case dataStorageError
        case dataDirectoryStats
        case dataDirectoryStatsError
        case proxyPort
        case proxyPortReadState
        case failureReasons
        case redisRelayStatus
    }

    public var runtimeInstalled: Bool
    public var runtimeInstallationState: RuntimeFileState?
    public var vmServiceLoaded: Bool
    public var proxyServiceLoaded: Bool
    public var guestLogSyncServiceLoaded: Bool
    public var sleepPreventionServiceLoaded: Bool?
    public var watchdogServiceLoaded: Bool
    public var vmServiceState: RuntimeServiceState?
    public var proxyServiceState: RuntimeServiceState?
    public var guestLogSyncServiceState: RuntimeServiceState?
    public var sleepPreventionServiceState: RuntimeServiceState?
    public var watchdogServiceState: RuntimeServiceState?
    public var vmServiceStateSource: RuntimeServiceStateSource?
    public var proxyServiceStateSource: RuntimeServiceStateSource?
    public var guestLogSyncServiceStateSource: RuntimeServiceStateSource?
    public var sleepPreventionServiceStateSource: RuntimeServiceStateSource?
    public var watchdogServiceStateSource: RuntimeServiceStateSource?
    public var runtimeState: RuntimeState?
    public var readIssues: [RuntimeStatusReadIssue]
    public var runtimeVersion: String?
    public var latestBackup: String?
    public var vmState: RuntimeVMState?
    public var vmErrors: [RuntimeVMError]?
    public var vmIP: String?
    public var guestHTTP: String?
    public var hostProxyHTTP: String?
    public var runtimeControlHTTP: String?
    public var runtimeControlStartedAt: String?
    public var redisUIHTTP: String?
    public var swaggerUIHTTP: String?
    public var guestServicesReadState: RuntimeGuestServicesReadState?
    public var guestServices: [String]?
    public var guestServiceStatuses: [RuntimeGuestControlServiceStatus]
    public var guestServiceResources: [RuntimeGuestServiceResource]
    public var guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue]
    public var guestStackProbeErrors: [GuestRuntimeProbeError]
    public var guestServicesReadError: String?
    public var cpuUsagePercent: Double?
    public var memory: ResourceUsage?
    public var vitalServerMemory: RuntimeContainerMemoryUsage?
    public var recorderIngressMemory: RuntimeContainerMemoryUsage?
    public var redisMemory: RuntimeContainerMemoryUsage?
    public var systemDisk: ResourceUsage?
    public var dataStorage: ResourceUsage?
    public var dataStorageError: String?
    public var dataDirectoryStats: RuntimeDataDirectoryStats?
    public var dataDirectoryStatsError: String?
    public var proxyPort: Int?
    public var proxyPortReadState: RuntimeProxyPortReadState?
    public var failureReasons: [RuntimeFailureReason]
    public var redisRelayStatus: RuntimeRedisRelayStatus?

    public init(
        runtimeInstalled: Bool = false,
        runtimeInstallationState: RuntimeFileState? = nil,
        vmServiceLoaded: Bool = false,
        proxyServiceLoaded: Bool = false,
        guestLogSyncServiceLoaded: Bool = false,
        sleepPreventionServiceLoaded: Bool? = nil,
        watchdogServiceLoaded: Bool = false,
        vmServiceState: RuntimeServiceState? = nil,
        proxyServiceState: RuntimeServiceState? = nil,
        guestLogSyncServiceState: RuntimeServiceState? = nil,
        sleepPreventionServiceState: RuntimeServiceState? = nil,
        watchdogServiceState: RuntimeServiceState? = nil,
        vmServiceStateSource: RuntimeServiceStateSource? = nil,
        proxyServiceStateSource: RuntimeServiceStateSource? = nil,
        guestLogSyncServiceStateSource: RuntimeServiceStateSource? = nil,
        sleepPreventionServiceStateSource: RuntimeServiceStateSource? = nil,
        watchdogServiceStateSource: RuntimeServiceStateSource? = nil,
        runtimeState: RuntimeState? = nil,
        readIssues: [RuntimeStatusReadIssue] = [],
        runtimeVersion: String? = nil,
        latestBackup: String? = nil,
        vmState: RuntimeVMState? = nil,
        vmErrors: [RuntimeVMError]? = nil,
        vmIP: String? = nil,
        guestHTTP: String? = nil,
        hostProxyHTTP: String? = nil,
        runtimeControlHTTP: String? = nil,
        runtimeControlStartedAt: String? = nil,
        redisUIHTTP: String? = nil,
        swaggerUIHTTP: String? = nil,
        guestServicesReadState: RuntimeGuestServicesReadState? = .unavailable,
        guestServices: [String]? = nil,
        guestServiceStatuses: [RuntimeGuestControlServiceStatus] = [],
        guestServiceResources: [RuntimeGuestServiceResource] = [],
        guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = [],
        guestStackProbeErrors: [GuestRuntimeProbeError] = [],
        guestServicesReadError: String? = nil,
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        vitalServerMemory: RuntimeContainerMemoryUsage? = nil,
        recorderIngressMemory: RuntimeContainerMemoryUsage? = nil,
        redisMemory: RuntimeContainerMemoryUsage? = nil,
        systemDisk: ResourceUsage? = nil,
        dataStorage: ResourceUsage? = nil,
        dataStorageError: String? = nil,
        dataDirectoryStats: RuntimeDataDirectoryStats? = nil,
        dataDirectoryStatsError: String? = nil,
        proxyPort: Int? = nil,
        proxyPortReadState: RuntimeProxyPortReadState? = nil,
        failureReasons: [RuntimeFailureReason] = [],
        redisRelayStatus: RuntimeRedisRelayStatus? = nil
    ) {
        self.runtimeInstalled = runtimeInstalled
        self.runtimeInstallationState = runtimeInstallationState
        self.vmServiceLoaded = vmServiceLoaded
        self.proxyServiceLoaded = proxyServiceLoaded
        self.guestLogSyncServiceLoaded = guestLogSyncServiceLoaded
        self.sleepPreventionServiceLoaded = sleepPreventionServiceLoaded
        self.watchdogServiceLoaded = watchdogServiceLoaded
        self.vmServiceState = vmServiceState
        self.proxyServiceState = proxyServiceState
        self.guestLogSyncServiceState = guestLogSyncServiceState
        self.sleepPreventionServiceState = sleepPreventionServiceState
        self.watchdogServiceState = watchdogServiceState
        self.vmServiceStateSource = vmServiceStateSource
        self.proxyServiceStateSource = proxyServiceStateSource
        self.guestLogSyncServiceStateSource = guestLogSyncServiceStateSource
        self.sleepPreventionServiceStateSource = sleepPreventionServiceStateSource
        self.watchdogServiceStateSource = watchdogServiceStateSource
        self.runtimeState = runtimeState
        self.readIssues = readIssues
        self.runtimeVersion = runtimeVersion
        self.latestBackup = latestBackup
        self.vmState = vmState
        self.vmErrors = vmErrors
        self.vmIP = vmIP
        self.guestHTTP = guestHTTP
        self.hostProxyHTTP = hostProxyHTTP
        self.runtimeControlHTTP = runtimeControlHTTP
        self.runtimeControlStartedAt = runtimeControlStartedAt
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.guestServicesReadState = guestServicesReadState
        self.guestServices = guestServices
        self.guestServiceStatuses = guestServiceStatuses
        self.guestServiceResources = guestServiceResources
        self.guestServiceResourceReadIssues = guestServiceResourceReadIssues
        self.guestStackProbeErrors = guestStackProbeErrors
        self.guestServicesReadError = guestServicesReadError
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.vitalServerMemory = vitalServerMemory
        self.recorderIngressMemory = recorderIngressMemory
        self.redisMemory = redisMemory
        self.systemDisk = systemDisk
        self.dataStorage = dataStorage
        self.dataStorageError = dataStorageError
        self.dataDirectoryStats = dataDirectoryStats
        self.dataDirectoryStatsError = dataDirectoryStatsError
        self.proxyPort = proxyPort
        self.proxyPortReadState = proxyPortReadState
        self.failureReasons = failureReasons
        self.redisRelayStatus = redisRelayStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let guestServicesReadState = try container.decodeIfPresent(
            RuntimeGuestServicesReadState.self,
            forKey: .guestServicesReadState
        ) ?? .unavailable
        let guestServiceStatuses: [RuntimeGuestControlServiceStatus]
        let guestServiceResources: [RuntimeGuestServiceResource]
        let guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue]
        switch guestServicesReadState {
        case .loaded:
            guestServiceStatuses = try Self.decodeRequiredArray(
                [RuntimeGuestControlServiceStatus].self,
                forKey: .guestServiceStatuses,
                from: container
            )
            guestServiceResources = try Self.decodeRequiredArray(
                [RuntimeGuestServiceResource].self,
                forKey: .guestServiceResources,
                from: container
            )
            guestServiceResourceReadIssues = try Self.decodeRequiredArray(
                [RuntimeGuestServiceResourceReadIssue].self,
                forKey: .guestServiceResourceReadIssues,
                from: container
            )
        case .unavailable, .failed:
            guestServiceStatuses = try container.decodeIfPresent(
                [RuntimeGuestControlServiceStatus].self,
                forKey: .guestServiceStatuses
            ) ?? []
            guestServiceResources = try container.decodeIfPresent(
                [RuntimeGuestServiceResource].self,
                forKey: .guestServiceResources
            ) ?? []
            guestServiceResourceReadIssues = try container.decodeIfPresent(
                [RuntimeGuestServiceResourceReadIssue].self,
                forKey: .guestServiceResourceReadIssues
            ) ?? []
        }
        let guestServicesReadError = try container.decodeIfPresent(
            String.self,
            forKey: .guestServicesReadError
        )
        if guestServicesReadState == .failed,
           guestServicesReadError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw DecodingError.dataCorruptedError(
                forKey: .guestServicesReadError,
                in: container,
                debugDescription: "failed guest service reads must include guestServicesReadError"
            )
        }
        self.init(
            runtimeInstalled: try container.decodeIfPresent(Bool.self, forKey: .runtimeInstalled) ?? false,
            runtimeInstallationState: try container.decodeIfPresent(RuntimeFileState.self, forKey: .runtimeInstallationState),
            vmServiceLoaded: try container.decodeIfPresent(Bool.self, forKey: .vmServiceLoaded) ?? false,
            proxyServiceLoaded: try container.decodeIfPresent(Bool.self, forKey: .proxyServiceLoaded) ?? false,
            guestLogSyncServiceLoaded: try container.decodeIfPresent(Bool.self, forKey: .guestLogSyncServiceLoaded) ?? false,
            sleepPreventionServiceLoaded: try container.decodeIfPresent(Bool.self, forKey: .sleepPreventionServiceLoaded),
            watchdogServiceLoaded: try container.decodeIfPresent(Bool.self, forKey: .watchdogServiceLoaded) ?? false,
            vmServiceState: try container.decodeIfPresent(RuntimeServiceState.self, forKey: .vmServiceState),
            proxyServiceState: try container.decodeIfPresent(RuntimeServiceState.self, forKey: .proxyServiceState),
            guestLogSyncServiceState: try container.decodeIfPresent(RuntimeServiceState.self, forKey: .guestLogSyncServiceState),
            sleepPreventionServiceState: try container.decodeIfPresent(RuntimeServiceState.self, forKey: .sleepPreventionServiceState),
            watchdogServiceState: try container.decodeIfPresent(RuntimeServiceState.self, forKey: .watchdogServiceState),
            vmServiceStateSource: try container.decodeIfPresent(RuntimeServiceStateSource.self, forKey: .vmServiceStateSource),
            proxyServiceStateSource: try container.decodeIfPresent(RuntimeServiceStateSource.self, forKey: .proxyServiceStateSource),
            guestLogSyncServiceStateSource: try container.decodeIfPresent(RuntimeServiceStateSource.self, forKey: .guestLogSyncServiceStateSource),
            sleepPreventionServiceStateSource: try container.decodeIfPresent(RuntimeServiceStateSource.self, forKey: .sleepPreventionServiceStateSource),
            watchdogServiceStateSource: try container.decodeIfPresent(RuntimeServiceStateSource.self, forKey: .watchdogServiceStateSource),
            runtimeState: try container.decodeIfPresent(RuntimeState.self, forKey: .runtimeState),
            readIssues: try container.decodeIfPresent([RuntimeStatusReadIssue].self, forKey: .readIssues) ?? [],
            runtimeVersion: try container.decodeIfPresent(String.self, forKey: .runtimeVersion),
            latestBackup: try container.decodeIfPresent(String.self, forKey: .latestBackup),
            vmState: try container.decodeIfPresent(RuntimeVMState.self, forKey: .vmState),
            vmErrors: try container.decodeIfPresent([RuntimeVMError].self, forKey: .vmErrors),
            vmIP: try container.decodeIfPresent(String.self, forKey: .vmIP),
            guestHTTP: try container.decodeIfPresent(String.self, forKey: .guestHTTP),
            hostProxyHTTP: try container.decodeIfPresent(String.self, forKey: .hostProxyHTTP),
            runtimeControlHTTP: try container.decodeIfPresent(String.self, forKey: .runtimeControlHTTP),
            runtimeControlStartedAt: try container.decodeIfPresent(String.self, forKey: .runtimeControlStartedAt),
            redisUIHTTP: try container.decodeIfPresent(String.self, forKey: .redisUIHTTP),
            swaggerUIHTTP: try container.decodeIfPresent(String.self, forKey: .swaggerUIHTTP),
            guestServicesReadState: guestServicesReadState,
            guestServices: try container.decodeIfPresent([String].self, forKey: .guestServices),
            guestServiceStatuses: guestServiceStatuses,
            guestServiceResources: guestServiceResources,
            guestServiceResourceReadIssues: guestServiceResourceReadIssues,
            guestStackProbeErrors: try container.decodeIfPresent([GuestRuntimeProbeError].self, forKey: .guestStackProbeErrors) ?? [],
            guestServicesReadError: guestServicesReadError,
            cpuUsagePercent: try container.decodeIfPresent(Double.self, forKey: .cpuUsagePercent),
            memory: try container.decodeIfPresent(ResourceUsage.self, forKey: .memory),
            vitalServerMemory: try container.decodeIfPresent(RuntimeContainerMemoryUsage.self, forKey: .vitalServerMemory),
            recorderIngressMemory: try container.decodeIfPresent(RuntimeContainerMemoryUsage.self, forKey: .recorderIngressMemory),
            redisMemory: try container.decodeIfPresent(RuntimeContainerMemoryUsage.self, forKey: .redisMemory),
            systemDisk: try container.decodeIfPresent(ResourceUsage.self, forKey: .systemDisk),
            dataStorage: try container.decodeIfPresent(ResourceUsage.self, forKey: .dataStorage),
            dataStorageError: try container.decodeIfPresent(String.self, forKey: .dataStorageError),
            dataDirectoryStats: try container.decodeIfPresent(RuntimeDataDirectoryStats.self, forKey: .dataDirectoryStats),
            dataDirectoryStatsError: try container.decodeIfPresent(String.self, forKey: .dataDirectoryStatsError),
            proxyPort: try container.decodeIfPresent(Int.self, forKey: .proxyPort),
            proxyPortReadState: try container.decodeIfPresent(RuntimeProxyPortReadState.self, forKey: .proxyPortReadState),
            failureReasons: try container.decodeIfPresent([RuntimeFailureReason].self, forKey: .failureReasons) ?? [],
            redisRelayStatus: try container.decodeIfPresent(RuntimeRedisRelayStatus.self, forKey: .redisRelayStatus)
        )
    }

    private static func decodeRequiredArray<T: Decodable>(
        _ type: [T].Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [T] {
        guard container.contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "loaded guest service reads must include \(key.stringValue)"
                )
            )
        }
        return try container.decode(type, forKey: key)
    }

}
