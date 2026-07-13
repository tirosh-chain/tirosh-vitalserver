import Foundation

public enum RuntimePlatformSettingsReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
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
        startOnBoot: Bool,
        startOnBootConfigurable: Bool,
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
        self.minimumDiskGiB = minimumDiskGiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.proxyPort = proxyPort
        self.runtimeControlPort = runtimeControlPort
        self.vitalFilesDirectory = vitalFilesDirectory
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
