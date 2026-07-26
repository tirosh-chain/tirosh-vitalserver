import Foundation

public enum RuntimePlatformSettingsReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
}

public struct RuntimePlatformAppliedVMSettingsDocument: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case cpuCount
        case memoryGiB
        case networkMode
        case bridgedInterface
        case vitalFilesDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cpuCount: try container.decode(Int.self, forKey: .cpuCount),
            memoryGiB: try container.decode(Int.self, forKey: .memoryGiB),
            networkMode: try container.decode(RuntimeNetworkMode.self, forKey: .networkMode),
            bridgedInterface: try container.decodeRequiredNullable(String.self, forKey: .bridgedInterface),
            vitalFilesDirectory: try container.decode(String.self, forKey: .vitalFilesDirectory)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cpuCount, forKey: .cpuCount)
        try container.encode(memoryGiB, forKey: .memoryGiB)
        try container.encode(networkMode, forKey: .networkMode)
        try container.encodeRequiredNullable(bridgedInterface, forKey: .bridgedInterface)
        try container.encode(vitalFilesDirectory, forKey: .vitalFilesDirectory)
    }
}

/// Platform Agent-owned settings that are safe to expose to browser clients.
/// Runtime Controller settings and credentials are intentionally excluded.
public struct RuntimePlatformSettingsDocument: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memoryGiB: Int
    public let diskGiB: Int
    public let minimumDiskGiB: Int
    public let networkMode: RuntimeNetworkMode
    public let bridgedInterface: String?
    public let proxyPort: Int
    public let runtimeControlPort: Int
    public let vitalFilesDirectory: String
    public let vitalServerURL: String
    public let remoteConsoleURL: String
    public let publicHost: String
    public let publicPort: Int
    public let recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode
    public let recorderIngressSendDataReplayBatchSize: Int
    public let recorderIngressSendDataReplayMaxMiBPerSecond: Int
    public let recorderIngress: RuntimeRecorderIngressSettings
    public let containerMemoryLimitsEnabled: Bool
    public let vitalServerContainerMemoryLimitMiB: Int
    public let recorderIngressContainerMemoryLimitMiB: Int
    public let redisContainerMemoryLimitMiB: Int
    public let startOnBoot: Bool
    public let startOnBootConfigurable: Bool
    public let autoRecoveryEnabled: Bool
    public let preventSystemSleep: Bool
    public let automaticBackupEnabled: Bool
    public let backupScheduleTimes: [String]
    public let backupRetentionCount: Int
    public let logArchiveRetentionDays: Int
    public let logArchiveMaximumGiB: Int
    public let restartAfterSave: Bool
    public let appliedVMSettings: RuntimePlatformAppliedVMSettingsDocument?

    public init(
        cpuCount: Int,
        memoryGiB: Int,
        diskGiB: Int,
        minimumDiskGiB: Int,
        networkMode: RuntimeNetworkMode,
        bridgedInterface: String?,
        proxyPort: Int,
        runtimeControlPort: Int,
        vitalFilesDirectory: String,
        vitalServerURL: String,
        remoteConsoleURL: String,
        publicHost: String,
        publicPort: Int,
        recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode,
        recorderIngressSendDataReplayBatchSize: Int,
        recorderIngressSendDataReplayMaxMiBPerSecond: Int,
        recorderIngress: RuntimeRecorderIngressSettings,
        containerMemoryLimitsEnabled: Bool,
        vitalServerContainerMemoryLimitMiB: Int,
        recorderIngressContainerMemoryLimitMiB: Int,
        redisContainerMemoryLimitMiB: Int,
        startOnBoot: Bool,
        startOnBootConfigurable: Bool,
        autoRecoveryEnabled: Bool,
        preventSystemSleep: Bool,
        automaticBackupEnabled: Bool,
        backupScheduleTimes: [String],
        backupRetentionCount: Int,
        logArchiveRetentionDays: Int,
        logArchiveMaximumGiB: Int,
        restartAfterSave: Bool,
        appliedVMSettings: RuntimePlatformAppliedVMSettingsDocument?
    ) {
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
        self.recorderIngressSendDataReplayBatchSize = recorderIngressSendDataReplayBatchSize
        self.recorderIngressSendDataReplayMaxMiBPerSecond = recorderIngressSendDataReplayMaxMiBPerSecond
        self.recorderIngress = recorderIngress
        self.containerMemoryLimitsEnabled = containerMemoryLimitsEnabled
        self.vitalServerContainerMemoryLimitMiB = vitalServerContainerMemoryLimitMiB
        self.recorderIngressContainerMemoryLimitMiB = recorderIngressContainerMemoryLimitMiB
        self.redisContainerMemoryLimitMiB = redisContainerMemoryLimitMiB
        self.startOnBoot = startOnBoot
        self.startOnBootConfigurable = startOnBootConfigurable
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
        self.automaticBackupEnabled = automaticBackupEnabled
        self.backupScheduleTimes = backupScheduleTimes
        self.backupRetentionCount = backupRetentionCount
        self.logArchiveRetentionDays = logArchiveRetentionDays
        self.logArchiveMaximumGiB = logArchiveMaximumGiB
        self.restartAfterSave = restartAfterSave
        self.appliedVMSettings = appliedVMSettings
    }

    private enum CodingKeys: String, CodingKey {
        case cpuCount, memoryGiB, diskGiB, minimumDiskGiB, networkMode, bridgedInterface
        case proxyPort, runtimeControlPort, vitalFilesDirectory, vitalServerURL, remoteConsoleURL
        case publicHost, publicPort, recorderIngressSendDataMode
        case recorderIngressSendDataReplayBatchSize, recorderIngressSendDataReplayMaxMiBPerSecond
        case recorderIngress, containerMemoryLimitsEnabled, vitalServerContainerMemoryLimitMiB
        case recorderIngressContainerMemoryLimitMiB, redisContainerMemoryLimitMiB
        case startOnBoot, startOnBootConfigurable, autoRecoveryEnabled, preventSystemSleep
        case automaticBackupEnabled, backupScheduleTimes, backupRetentionCount
        case logArchiveRetentionDays, logArchiveMaximumGiB, restartAfterSave, appliedVMSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cpuCount: try container.decode(Int.self, forKey: .cpuCount),
            memoryGiB: try container.decode(Int.self, forKey: .memoryGiB),
            diskGiB: try container.decode(Int.self, forKey: .diskGiB),
            minimumDiskGiB: try container.decode(Int.self, forKey: .minimumDiskGiB),
            networkMode: try container.decode(RuntimeNetworkMode.self, forKey: .networkMode),
            bridgedInterface: try container.decodeRequiredNullable(String.self, forKey: .bridgedInterface),
            proxyPort: try container.decode(Int.self, forKey: .proxyPort),
            runtimeControlPort: try container.decode(Int.self, forKey: .runtimeControlPort),
            vitalFilesDirectory: try container.decode(String.self, forKey: .vitalFilesDirectory),
            vitalServerURL: try container.decode(String.self, forKey: .vitalServerURL),
            remoteConsoleURL: try container.decode(String.self, forKey: .remoteConsoleURL),
            publicHost: try container.decode(String.self, forKey: .publicHost),
            publicPort: try container.decode(Int.self, forKey: .publicPort),
            recorderIngressSendDataMode: try container.decode(RuntimeRecorderIngressSendDataMode.self, forKey: .recorderIngressSendDataMode),
            recorderIngressSendDataReplayBatchSize: try container.decode(Int.self, forKey: .recorderIngressSendDataReplayBatchSize),
            recorderIngressSendDataReplayMaxMiBPerSecond: try container.decode(Int.self, forKey: .recorderIngressSendDataReplayMaxMiBPerSecond),
            recorderIngress: try container.decode(RuntimeRecorderIngressSettings.self, forKey: .recorderIngress),
            containerMemoryLimitsEnabled: try container.decode(Bool.self, forKey: .containerMemoryLimitsEnabled),
            vitalServerContainerMemoryLimitMiB: try container.decode(Int.self, forKey: .vitalServerContainerMemoryLimitMiB),
            recorderIngressContainerMemoryLimitMiB: try container.decode(Int.self, forKey: .recorderIngressContainerMemoryLimitMiB),
            redisContainerMemoryLimitMiB: try container.decode(Int.self, forKey: .redisContainerMemoryLimitMiB),
            startOnBoot: try container.decode(Bool.self, forKey: .startOnBoot),
            startOnBootConfigurable: try container.decode(Bool.self, forKey: .startOnBootConfigurable),
            autoRecoveryEnabled: try container.decode(Bool.self, forKey: .autoRecoveryEnabled),
            preventSystemSleep: try container.decode(Bool.self, forKey: .preventSystemSleep),
            automaticBackupEnabled: try container.decode(Bool.self, forKey: .automaticBackupEnabled),
            backupScheduleTimes: try container.decode([String].self, forKey: .backupScheduleTimes),
            backupRetentionCount: try container.decode(Int.self, forKey: .backupRetentionCount),
            logArchiveRetentionDays: try container.decode(Int.self, forKey: .logArchiveRetentionDays),
            logArchiveMaximumGiB: try container.decode(Int.self, forKey: .logArchiveMaximumGiB),
            restartAfterSave: try container.decode(Bool.self, forKey: .restartAfterSave),
            appliedVMSettings: try container.decodeRequiredNullable(RuntimePlatformAppliedVMSettingsDocument.self, forKey: .appliedVMSettings)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cpuCount, forKey: .cpuCount)
        try container.encode(memoryGiB, forKey: .memoryGiB)
        try container.encode(diskGiB, forKey: .diskGiB)
        try container.encode(minimumDiskGiB, forKey: .minimumDiskGiB)
        try container.encode(networkMode, forKey: .networkMode)
        try container.encodeRequiredNullable(bridgedInterface, forKey: .bridgedInterface)
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(runtimeControlPort, forKey: .runtimeControlPort)
        try container.encode(vitalFilesDirectory, forKey: .vitalFilesDirectory)
        try container.encode(vitalServerURL, forKey: .vitalServerURL)
        try container.encode(remoteConsoleURL, forKey: .remoteConsoleURL)
        try container.encode(publicHost, forKey: .publicHost)
        try container.encode(publicPort, forKey: .publicPort)
        try container.encode(recorderIngressSendDataMode, forKey: .recorderIngressSendDataMode)
        try container.encode(recorderIngressSendDataReplayBatchSize, forKey: .recorderIngressSendDataReplayBatchSize)
        try container.encode(recorderIngressSendDataReplayMaxMiBPerSecond, forKey: .recorderIngressSendDataReplayMaxMiBPerSecond)
        try container.encode(recorderIngress, forKey: .recorderIngress)
        try container.encode(containerMemoryLimitsEnabled, forKey: .containerMemoryLimitsEnabled)
        try container.encode(vitalServerContainerMemoryLimitMiB, forKey: .vitalServerContainerMemoryLimitMiB)
        try container.encode(recorderIngressContainerMemoryLimitMiB, forKey: .recorderIngressContainerMemoryLimitMiB)
        try container.encode(redisContainerMemoryLimitMiB, forKey: .redisContainerMemoryLimitMiB)
        try container.encode(startOnBoot, forKey: .startOnBoot)
        try container.encode(startOnBootConfigurable, forKey: .startOnBootConfigurable)
        try container.encode(autoRecoveryEnabled, forKey: .autoRecoveryEnabled)
        try container.encode(preventSystemSleep, forKey: .preventSystemSleep)
        try container.encode(automaticBackupEnabled, forKey: .automaticBackupEnabled)
        try container.encode(backupScheduleTimes, forKey: .backupScheduleTimes)
        try container.encode(backupRetentionCount, forKey: .backupRetentionCount)
        try container.encode(logArchiveRetentionDays, forKey: .logArchiveRetentionDays)
        try container.encode(logArchiveMaximumGiB, forKey: .logArchiveMaximumGiB)
        try container.encode(restartAfterSave, forKey: .restartAfterSave)
        try container.encodeRequiredNullable(appliedVMSettings, forKey: .appliedVMSettings)
    }
}

public struct RuntimePlatformSettingsReadIssue: Codable, Equatable, Sendable {
    public let source: String
    public let message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public struct RuntimePlatformSettingsRead: Codable, Equatable, Sendable {
    public let state: RuntimePlatformSettingsReadState
    public let settings: RuntimePlatformSettingsDocument?
    public let readIssues: [RuntimePlatformSettingsReadIssue]
    public let readError: String?

    public init(
        state: RuntimePlatformSettingsReadState,
        settings: RuntimePlatformSettingsDocument?,
        readIssues: [RuntimePlatformSettingsReadIssue],
        readError: String?
    ) {
        self.state = state
        self.settings = settings
        self.readIssues = readIssues
        self.readError = readError
    }

    private enum CodingKeys: String, CodingKey {
        case state, settings, readIssues, readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            state: try container.decode(RuntimePlatformSettingsReadState.self, forKey: .state),
            settings: try container.decodeRequiredNullable(RuntimePlatformSettingsDocument.self, forKey: .settings),
            readIssues: try container.decode([RuntimePlatformSettingsReadIssue].self, forKey: .readIssues),
            readError: try container.decodeRequiredNullable(String.self, forKey: .readError)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encodeRequiredNullable(settings, forKey: .settings)
        try container.encode(readIssues, forKey: .readIssues)
        try container.encodeRequiredNullable(readError, forKey: .readError)
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredNullable<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Required nullable field is missing: \(key.stringValue)"
                )
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeRequiredNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

public struct RuntimePlatformSettingsApplyDocument: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memoryGiB: Int
    public let diskGiB: Int
    public let networkMode: RuntimeNetworkMode
    public let bridgedInterface: String?
    public let proxyPort: Int
    public let runtimeControlPort: Int
    public let vitalFilesDirectory: String
    public let startOnBoot: Bool
    public let autoRecoveryEnabled: Bool
    public let preventSystemSleep: Bool
    public let automaticBackupEnabled: Bool
    public let backupScheduleTimes: [String]
    public let backupRetentionCount: Int
    public let logArchiveRetentionDays: Int
    public let logArchiveMaximumGiB: Int
    public let restartAfterSave: Bool

    public init(
        cpuCount: Int,
        memoryGiB: Int,
        diskGiB: Int,
        networkMode: RuntimeNetworkMode,
        bridgedInterface: String?,
        proxyPort: Int,
        runtimeControlPort: Int,
        vitalFilesDirectory: String,
        startOnBoot: Bool,
        autoRecoveryEnabled: Bool,
        preventSystemSleep: Bool,
        automaticBackupEnabled: Bool,
        backupScheduleTimes: [String],
        backupRetentionCount: Int,
        logArchiveRetentionDays: Int,
        logArchiveMaximumGiB: Int,
        restartAfterSave: Bool
    ) {
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.proxyPort = proxyPort
        self.runtimeControlPort = runtimeControlPort
        self.vitalFilesDirectory = vitalFilesDirectory
        self.startOnBoot = startOnBoot
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
        self.automaticBackupEnabled = automaticBackupEnabled
        self.backupScheduleTimes = backupScheduleTimes
        self.backupRetentionCount = backupRetentionCount
        self.logArchiveRetentionDays = logArchiveRetentionDays
        self.logArchiveMaximumGiB = logArchiveMaximumGiB
        self.restartAfterSave = restartAfterSave
    }

}

public struct RuntimeApplyPlatformSettingsRequest: Codable, Equatable, Sendable {
    public let settings: RuntimePlatformSettingsApplyDocument

    public init(settings: RuntimePlatformSettingsApplyDocument) {
        self.settings = settings
    }
}
