import Foundation
import Contracts
import Errors

public struct RuntimeControlCapabilities: Codable, Equatable, Sendable {
    public var canInstallRuntime: Bool
    public var canUninstallRuntime: Bool
    public var canApplyBundle: Bool
    public var canRollback: Bool
    public var canRollbackRelease: Bool
    public var canEditRuntimeProviderResources: Bool
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
        canApplyBundle: Bool = false,
        canRollback: Bool = true,
        canRollbackRelease: Bool = false,
        canEditRuntimeProviderResources: Bool = true,
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
        self.canRollbackRelease = canRollbackRelease
        self.canEditRuntimeProviderResources = canEditRuntimeProviderResources
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

/// Capabilities owned by the Platform Agent. This contract deliberately omits
/// Runtime Controller product capabilities such as service control and Lab.
public struct PlatformCapabilities: Codable, Equatable, Sendable {
    public var canInstallRuntime: Bool
    public var canUninstallRuntime: Bool
    public var canApplyBundle: Bool
    public var canRollback: Bool
    public var canRollbackRelease: Bool
    public var canEditRuntimeProviderResources: Bool
    public var canEditNetworkExposure: Bool
    public var canResetAdminPassword: Bool
    public var canOpenLocalFiles: Bool
    public var canStreamLogs: Bool
    public var canControlRuntimeServices: Bool
    public var canExportLogs: Bool
    public var canViewReleaseMetadata: Bool

    public init(_ capabilities: RuntimeControlCapabilities = RuntimeControlCapabilities()) {
        self.canInstallRuntime = capabilities.canInstallRuntime
        self.canUninstallRuntime = capabilities.canUninstallRuntime
        self.canApplyBundle = capabilities.canApplyBundle
        self.canRollback = capabilities.canRollback
        self.canRollbackRelease = capabilities.canRollbackRelease
        self.canEditRuntimeProviderResources = capabilities.canEditRuntimeProviderResources
        self.canEditNetworkExposure = capabilities.canEditNetworkExposure
        self.canResetAdminPassword = capabilities.canResetAdminPassword
        self.canOpenLocalFiles = capabilities.canOpenLocalFiles
        self.canStreamLogs = capabilities.canStreamLogs
        self.canControlRuntimeServices = capabilities.canControlRuntimeServices
        self.canExportLogs = capabilities.canExportLogs
        self.canViewReleaseMetadata = capabilities.canViewReleaseMetadata
    }
}

/// Runtime Controller-owned capability document. Values are passed through
/// from the Runtime Controller and are not reconstructed from Platform state.
public struct RuntimeCapabilities: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let capabilities: [String]

    public init(schemaVersion: Int, capabilities: [String]) {
        self.schemaVersion = schemaVersion
        self.capabilities = capabilities
    }

    public init(_ document: RuntimeGuestControlCapabilities) {
        self.init(
            schemaVersion: document.schemaVersion,
            capabilities: document.capabilities
        )
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
    public var clearUsername: Bool
    public var usernameConfigured: Bool
    public var passwordConfigured: Bool
    public var tls: Bool

    public init(
        url: String = RuntimeRedisRelayTarget.defaultURL,
        username: String = "",
        password: String = "",
        clearPassword: Bool = false,
        clearUsername: Bool = false,
        usernameConfigured: Bool = false,
        passwordConfigured: Bool = false,
        tls: Bool = false
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.clearPassword = clearPassword
        self.clearUsername = clearUsername
        self.usernameConfigured = usernameConfigured
        self.passwordConfigured = passwordConfigured
        self.tls = tls
    }

    enum CodingKeys: String, CodingKey {
        case url
        case username
        case password
        case clearPassword
        case clearUsername
        case usernameConfigured
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
            clearUsername: try container.decodeIfPresent(Bool.self, forKey: .clearUsername) ?? false,
            usernameConfigured: try container.decodeIfPresent(Bool.self, forKey: .usernameConfigured) ?? false,
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

public struct PlatformStateReadIssue: Codable, Equatable, Sendable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public enum PlatformServiceRole: String, Codable, Equatable, Sendable {
    case runtimeProvider = "runtime-provider"
    case publicProxy = "public-proxy"
    case logSync = "log-sync"
    case sleepPrevention = "sleep-prevention"
    case watchdog
}

public enum PlatformServiceState: String, Codable, Equatable, Sendable {
    case running
    case stopped
    case notInstalled = "not-installed"
    case unavailable
    case readFailed = "read-failed"
    case permissionDenied = "permission-denied"
    case failed
}

public struct PlatformServiceStatus: Codable, Equatable, Sendable {
    public let role: PlatformServiceRole
    public let state: PlatformServiceState
    public let readError: String?

    public init(
        role: PlatformServiceRole,
        state: PlatformServiceState,
        readError: String? = nil
    ) {
        self.role = role
        self.state = state
        self.readError = readError
    }

    public init(role: PlatformServiceRole, state: RuntimeServiceState) {
        self.role = role
        switch state {
        case .loaded:
            self.state = .running
            self.readError = nil
        case .notLoaded:
            self.state = .stopped
            self.readError = nil
        case .readFailed(let reason):
            self.state = .readFailed
            self.readError = reason.isEmpty ? "platform service state read failed" : reason
        case .permissionDenied(let reason):
            self.state = .permissionDenied
            self.readError = reason.isEmpty ? "platform service state permission denied" : reason
        case .unknown(let reason):
            self.state = .unavailable
            self.readError = reason.isEmpty ? "platform service state unavailable" : reason
        }
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case state
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(PlatformServiceRole.self, forKey: .role)
        let state = try container.decode(PlatformServiceState.self, forKey: .state)
        guard container.contains(.readError) else {
            throw DecodingError.keyNotFound(
                CodingKeys.readError,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Platform service readError must be explicit null or string"
                )
            )
        }
        let readError = try container.decodeIfPresent(String.self, forKey: .readError)
        let readErrorIsBlank = readError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        if [.unavailable, .readFailed, .permissionDenied, .failed].contains(state) && readErrorIsBlank {
            throw DecodingError.dataCorruptedError(
                forKey: .readError,
                in: container,
                debugDescription: "failed Platform service state must include readError"
            )
        }
        self.init(role: role, state: state, readError: readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(state, forKey: .state)
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    public var runtimeServiceState: RuntimeServiceState {
        switch state {
        case .running:
            .loaded
        case .stopped, .notInstalled:
            .notLoaded
        case .unavailable:
            .unknown(readError ?? "platform service state unavailable")
        case .readFailed:
            .readFailed(readError ?? "platform service state read failed")
        case .permissionDenied:
            .permissionDenied(readError ?? "platform service state permission denied")
        case .failed:
            .readFailed(readError ?? "platform service state read failed")
        }
    }
}

public struct PlatformState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case runtimeInstallationState
        case services
        case platformHealth
        case readIssues
        case installedVersion
        case latestBackup
        case runtimeProviderState
        case runtimeProviderErrors
        case runtimeEndpoint
        case runtimeControllerHTTP
        case publicProxyHTTP
        case platformAPIHTTP
        case platformAPIStartedAt
        case dataStorage
        case dataStorageError
        case dataDirectoryStats
        case dataDirectoryStatsError
        case publicProxyPort
        case publicProxyPortReadState
        case healthIssues
        case timeAuthority
    }

    public var runtimeInstallationState: RuntimeFileState
    public var services: [PlatformServiceStatus]
    public var platformHealth: RuntimeState?
    public var readIssues: [PlatformStateReadIssue]
    public var installedVersion: String?
    public var latestBackup: String?
    public var runtimeProviderState: RuntimeVMState?
    public var runtimeProviderErrors: [RuntimeVMError]?
    public var runtimeEndpoint: String?
    public var runtimeControllerHTTP: String?
    public var publicProxyHTTP: String?
    public var platformAPIHTTP: String?
    public var platformAPIStartedAt: String?
    public var dataStorage: ResourceUsage?
    public var dataStorageError: String?
    public var dataDirectoryStats: RuntimeDataDirectoryStats?
    public var dataDirectoryStatsError: String?
    public var publicProxyPort: Int?
    public var publicProxyPortReadState: RuntimeProxyPortReadState?
    public var healthIssues: [RuntimeFailureReason]
    public var timeAuthority: RuntimeTimeAuthorityResourceRead?

    public init(
        runtimeInstallationState: RuntimeFileState,
        services: [PlatformServiceStatus] = [],
        platformHealth: RuntimeState? = nil,
        readIssues: [PlatformStateReadIssue] = [],
        installedVersion: String? = nil,
        latestBackup: String? = nil,
        runtimeProviderState: RuntimeVMState? = nil,
        runtimeProviderErrors: [RuntimeVMError]? = nil,
        runtimeEndpoint: String? = nil,
        runtimeControllerHTTP: String? = nil,
        publicProxyHTTP: String? = nil,
        platformAPIHTTP: String? = nil,
        platformAPIStartedAt: String? = nil,
        dataStorage: ResourceUsage? = nil,
        dataStorageError: String? = nil,
        dataDirectoryStats: RuntimeDataDirectoryStats? = nil,
        dataDirectoryStatsError: String? = nil,
        publicProxyPort: Int? = nil,
        publicProxyPortReadState: RuntimeProxyPortReadState? = nil,
        healthIssues: [RuntimeFailureReason] = [],
        timeAuthority: RuntimeTimeAuthorityResourceRead? = nil
    ) {
        self.runtimeInstallationState = runtimeInstallationState
        self.services = services
        self.platformHealth = platformHealth
        self.readIssues = readIssues
        self.installedVersion = installedVersion
        self.latestBackup = latestBackup
        self.runtimeProviderState = runtimeProviderState
        self.runtimeProviderErrors = runtimeProviderErrors
        self.runtimeEndpoint = runtimeEndpoint
        self.runtimeControllerHTTP = runtimeControllerHTTP
        self.publicProxyHTTP = publicProxyHTTP
        self.platformAPIHTTP = platformAPIHTTP
        self.platformAPIStartedAt = platformAPIStartedAt
        self.dataStorage = dataStorage
        self.dataStorageError = dataStorageError
        self.dataDirectoryStats = dataDirectoryStats
        self.dataDirectoryStatsError = dataDirectoryStatsError
        self.publicProxyPort = publicProxyPort
        self.publicProxyPortReadState = publicProxyPortReadState
        self.healthIssues = healthIssues
        self.timeAuthority = timeAuthority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            runtimeInstallationState: try container.decode(RuntimeFileState.self, forKey: .runtimeInstallationState),
            services: try container.decode([PlatformServiceStatus].self, forKey: .services),
            platformHealth: try container.decodeIfPresent(RuntimeState.self, forKey: .platformHealth),
            readIssues: try container.decodeIfPresent([PlatformStateReadIssue].self, forKey: .readIssues) ?? [],
            installedVersion: try container.decodeIfPresent(String.self, forKey: .installedVersion),
            latestBackup: try container.decodeIfPresent(String.self, forKey: .latestBackup),
            runtimeProviderState: try container.decodeIfPresent(RuntimeVMState.self, forKey: .runtimeProviderState),
            runtimeProviderErrors: try container.decodeIfPresent([RuntimeVMError].self, forKey: .runtimeProviderErrors),
            runtimeEndpoint: try container.decodeIfPresent(String.self, forKey: .runtimeEndpoint),
            runtimeControllerHTTP: try container.decodeIfPresent(String.self, forKey: .runtimeControllerHTTP),
            publicProxyHTTP: try container.decodeIfPresent(String.self, forKey: .publicProxyHTTP),
            platformAPIHTTP: try container.decodeIfPresent(String.self, forKey: .platformAPIHTTP),
            platformAPIStartedAt: try container.decodeIfPresent(String.self, forKey: .platformAPIStartedAt),
            dataStorage: try container.decodeIfPresent(ResourceUsage.self, forKey: .dataStorage),
            dataStorageError: try container.decodeIfPresent(String.self, forKey: .dataStorageError),
            dataDirectoryStats: try container.decodeIfPresent(RuntimeDataDirectoryStats.self, forKey: .dataDirectoryStats),
            dataDirectoryStatsError: try container.decodeIfPresent(String.self, forKey: .dataDirectoryStatsError),
            publicProxyPort: try container.decodeIfPresent(Int.self, forKey: .publicProxyPort),
            publicProxyPortReadState: try container.decodeIfPresent(RuntimeProxyPortReadState.self, forKey: .publicProxyPortReadState),
            healthIssues: try container.decodeIfPresent([RuntimeFailureReason].self, forKey: .healthIssues) ?? [],
            timeAuthority: try container.decodeIfPresent(RuntimeTimeAuthorityResourceRead.self, forKey: .timeAuthority)
        )
    }

    public func serviceState(_ role: PlatformServiceRole) -> RuntimeServiceState? {
        services.first(where: { $0.role == role })?.runtimeServiceState
    }

}
