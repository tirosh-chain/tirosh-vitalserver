public struct RuntimeVMConfigSettingsReadInput: Equatable, Sendable {
    public let cpuCount: Int
    public let memoryMiB: UInt64
    public let networkMode: String
    public let bridgedInterface: String?
    public let vitalFilesDirectoryHostPath: String?
    public let autoRecoveryEnabled: Bool?
    public let preventSystemSleep: Bool?

    public init(
        cpuCount: Int,
        memoryMiB: UInt64,
        networkMode: String,
        bridgedInterface: String?,
        vitalFilesDirectoryHostPath: String?,
        autoRecoveryEnabled: Bool?,
        preventSystemSleep: Bool?
    ) {
        self.cpuCount = cpuCount
        self.memoryMiB = memoryMiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.vitalFilesDirectoryHostPath = vitalFilesDirectoryHostPath
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
    }
}

public struct RuntimeGuestRuntimeSettingsReadInput: Equatable, Sendable {
    public let vitalServerURL: String
    public let remoteConsoleURL: String
    public let publicHost: String
    public let publicPort: Int
    public let automaticBackupEnabled: Bool
    public let backupScheduleTimes: [String]
    public let backupRetentionCount: Int

    public init(
        vitalServerURL: String,
        remoteConsoleURL: String,
        publicHost: String,
        publicPort: Int,
        automaticBackupEnabled: Bool,
        backupScheduleTimes: [String],
        backupRetentionCount: Int
    ) {
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.automaticBackupEnabled = automaticBackupEnabled
        self.backupScheduleTimes = backupScheduleTimes
        self.backupRetentionCount = backupRetentionCount
    }
}

public struct RuntimeLogArchiveSettingsReadInput: Equatable, Sendable {
    public let retentionDays: Int
    public let maximumGiB: Int

    public init(retentionDays: Int, maximumGiB: Int) {
        self.retentionDays = retentionDays
        self.maximumGiB = maximumGiB
    }
}

public enum RuntimeSettingsReadResult<Value: Sendable>: Sendable {
    case missing
    case loaded(Value)
    case failed(String)
}

extension RuntimeSettingsReadResult: Equatable where Value: Equatable {}

public struct RuntimeSettingsReadSnapshot: Equatable, Sendable {
    public let vmConfig: RuntimeSettingsReadResult<RuntimeVMConfigSettingsReadInput>
    public let appliedVMConfig: RuntimeSettingsReadResult<RuntimeVMConfigSettingsReadInput>
    public let diskGiB: RuntimeSettingsReadResult<Int>
    public let guestRuntimeSettings: RuntimeSettingsReadResult<RuntimeGuestRuntimeSettingsReadInput>
    public let logArchiveSettings: RuntimeSettingsReadResult<RuntimeLogArchiveSettingsReadInput>
    public let proxyPort: RuntimeSettingsReadResult<Int>
    public let startOnBoot: RuntimeSettingsReadResult<Bool>

    public init(
        vmConfig: RuntimeSettingsReadResult<RuntimeVMConfigSettingsReadInput>,
        appliedVMConfig: RuntimeSettingsReadResult<RuntimeVMConfigSettingsReadInput> = .missing,
        diskGiB: RuntimeSettingsReadResult<Int>,
        guestRuntimeSettings: RuntimeSettingsReadResult<RuntimeGuestRuntimeSettingsReadInput>,
        logArchiveSettings: RuntimeSettingsReadResult<RuntimeLogArchiveSettingsReadInput> = .missing,
        proxyPort: RuntimeSettingsReadResult<Int>,
        startOnBoot: RuntimeSettingsReadResult<Bool>
    ) {
        self.vmConfig = vmConfig
        self.appliedVMConfig = appliedVMConfig
        self.diskGiB = diskGiB
        self.guestRuntimeSettings = guestRuntimeSettings
        self.logArchiveSettings = logArchiveSettings
        self.proxyPort = proxyPort
        self.startOnBoot = startOnBoot
    }
}

public enum RuntimeSettingsReadPolicy {
    public static func settings(
        from snapshot: RuntimeSettingsReadSnapshot,
        base: RuntimeSettings = RuntimeSettings()
    ) -> RuntimeSettings {
        var settings = base

        switch snapshot.vmConfig {
        case .loaded(let vmConfig):
            settings = applyVMConfig(vmConfig, to: settings)
        case .missing:
            break
        case .failed(let message):
            settings = appendReadIssue(source: "vmConfig", message: message, to: settings)
        }

        switch snapshot.diskGiB {
        case .loaded(let diskGiB):
            settings = applyDiskSizeGiB(diskGiB, to: settings)
        case .missing:
            break
        case .failed(let message):
            settings = appendReadIssue(source: "vmDisk", message: message, to: settings)
        }

        switch snapshot.appliedVMConfig {
        case .loaded(let appliedVMConfig):
            settings = applyAppliedVMConfig(appliedVMConfig, to: settings)
        case .missing:
            break
        case .failed(let message):
            settings = appendReadIssue(source: "appliedVMConfig", message: message, to: settings)
        }

        switch snapshot.guestRuntimeSettings {
        case .loaded(let guestSettings):
            settings = applyGuestRuntimeSettings(guestSettings, to: settings)
        case .missing:
            settings = appendReadIssue(
                source: "guestRuntimeSettings",
                message: "runtime settings document is missing",
                to: settings
            )
        case .failed(let message):
            settings = appendReadIssue(source: "guestRuntimeSettings", message: message, to: settings)
        }

        switch snapshot.logArchiveSettings {
        case .loaded(let logArchiveSettings):
            settings = applyLogArchiveSettings(logArchiveSettings, to: settings)
        case .missing:
            break
        case .failed(let message):
            settings = appendReadIssue(source: "logArchiveSettings", message: message, to: settings)
        }

        switch snapshot.proxyPort {
        case .loaded(let proxyPort):
            settings = applyProxyPort(proxyPort, to: settings)
        case .missing:
            break
        case .failed(let message):
            settings = appendReadIssue(source: "proxyLaunchDaemon", message: message, to: settings)
        }

        switch snapshot.startOnBoot {
        case .loaded(let startOnBoot):
            settings = applyStartOnBoot(startOnBoot, configurable: true, to: settings)
        case .missing:
            settings = applyStartOnBootMissing(to: settings)
        case .failed(let message):
            settings = appendReadIssue(
                source: "startOnBoot",
                message: message,
                to: applyStartOnBootMissing(to: settings)
            )
        }

        return settings
    }

    public static func applyAppliedVMConfig(
        _ input: RuntimeVMConfigSettingsReadInput,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        guard let networkMode = RuntimeNetworkMode(rawValue: input.networkMode) else {
            return appendReadIssue(
                source: "appliedVMConfig.network.mode",
                message: "network mode is invalid: \(input.networkMode)",
                to: settings
            )
        }
        if networkMode == .bridged,
           input.bridgedInterface?.isEmpty != false {
            return appendReadIssue(
                source: "appliedVMConfig.network.bridgedInterface",
                message: "bridgedInterface is missing for bridged network mode",
                to: settings
            )
        }
        guard let vitalFilesDirectoryHostPath = input.vitalFilesDirectoryHostPath else {
            return appendReadIssue(
                source: "appliedVMConfig.vitalFilesDirectory",
                message: "vitalFilesDirectory is missing",
                to: settings
            )
        }
        var next = settings
        next.appliedVMSettings = RuntimeAppliedVMSettings(
            cpuCount: input.cpuCount,
            memoryGiB: max(Int(input.memoryMiB / 1024), 1),
            networkMode: networkMode,
            bridgedInterface: input.bridgedInterface,
            vitalFilesDirectory: vitalFilesDirectoryHostPath
        )
        return next
    }

    public static func applyVMConfig(
        _ input: RuntimeVMConfigSettingsReadInput,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        var next = settings
        next.cpuCount = input.cpuCount
        next.memoryGiB = max(Int(input.memoryMiB / 1024), 1)
        next = applyNetworkSettings(mode: input.networkMode, bridgedInterface: input.bridgedInterface, to: next)
        if let vitalFilesDirectoryHostPath = input.vitalFilesDirectoryHostPath {
            next.vitalFilesDirectory = vitalFilesDirectoryHostPath
        }
        if let autoRecoveryEnabled = input.autoRecoveryEnabled {
            next.autoRecoveryEnabled = autoRecoveryEnabled
        } else {
            next = appendReadIssue(
                source: "vmConfig.autoRecoveryEnabled",
                message: "autoRecoveryEnabled is missing",
                to: next
            )
        }
        if let preventSystemSleep = input.preventSystemSleep {
            next.preventSystemSleep = preventSystemSleep
        } else {
            next = appendReadIssue(
                source: "vmConfig.preventSystemSleep",
                message: "preventSystemSleep is missing",
                to: next
            )
        }
        return next
    }

    public static func applyGuestRuntimeSettings(
        _ input: RuntimeGuestRuntimeSettingsReadInput,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        var next = settings
        next.vitalServerURL = input.vitalServerURL
        next.remoteConsoleURL = input.remoteConsoleURL
        next.publicHost = input.publicHost
        next.publicPort = input.publicPort
        next.automaticBackupEnabled = input.automaticBackupEnabled
        next.backupScheduleTimes = input.backupScheduleTimes
        next.backupRetentionCount = input.backupRetentionCount
        if !validBackupRetentionCount(input.backupRetentionCount) {
            next = appendReadIssue(
                source: "guestRuntimeSettings.backupRetentionCount",
                message: "backupRetentionCount is out of range: \(input.backupRetentionCount)",
                to: next
            )
        }
        return next
    }

    public static func applyLogArchiveSettings(
        _ input: RuntimeLogArchiveSettingsReadInput,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        var next = settings
        next.logArchiveRetentionDays = input.retentionDays
        next.logArchiveMaximumGiB = input.maximumGiB
        if !RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(input.retentionDays) {
            next = appendReadIssue(
                source: "logArchiveSettings.logArchiveRetentionDays",
                message: "logArchiveRetentionDays is out of range: \(input.retentionDays)",
                to: next
            )
        }
        if !validLogArchiveMaximumGiB(input.maximumGiB) {
            next = appendReadIssue(
                source: "logArchiveSettings.logArchiveMaximumGiB",
                message: "logArchiveMaximumGiB is out of range: \(input.maximumGiB)",
                to: next
            )
        }
        return next
    }

    public static func validLogArchiveMaximumGiB(_ gib: Int) -> Bool {
        (1...20).contains(gib)
    }

    private static func validBackupRetentionCount(_ count: Int) -> Bool {
        (1...30).contains(count)
    }

    public static func applyDiskSizeGiB(_ diskGiB: Int, to settings: RuntimeSettings) -> RuntimeSettings {
        var next = settings
        next.diskGiB = diskGiB
        next.minimumDiskGiB = diskGiB
        return next
    }

    public static func applyProxyPort(_ proxyPort: Int, to settings: RuntimeSettings) -> RuntimeSettings {
        var next = settings
        next.proxyPort = proxyPort
        return next
    }

    public static func applyStartOnBoot(
        _ startOnBoot: Bool,
        configurable: Bool,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        var next = settings
        next.startOnBoot = startOnBoot
        next.startOnBootConfigurable = configurable
        return next
    }

    public static func applyStartOnBootMissing(to settings: RuntimeSettings) -> RuntimeSettings {
        var next = settings
        next.startOnBootConfigurable = false
        return next
    }

    public static func appendReadIssue(
        source: String,
        message: String,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        var next = settings
        next.readIssues.append(RuntimeSettingsReadIssue(source: source, message: message))
        return next
    }

    private static func applyNetworkSettings(
        mode: String,
        bridgedInterface: String?,
        to settings: RuntimeSettings
    ) -> RuntimeSettings {
        var next = settings
        guard let networkMode = RuntimeNetworkMode(rawValue: mode) else {
            return appendReadIssue(
                source: "vmConfig.network.mode",
                message: "network mode is invalid: \(mode)",
                to: next
            )
        }

        next.networkMode = networkMode
        switch networkMode {
        case .shared:
            next.bridgedInterface = bridgedInterface
        case .bridged:
            guard let bridgedInterface, !bridgedInterface.isEmpty else {
                return appendReadIssue(
                    source: "vmConfig.network.bridgedInterface",
                    message: "bridgedInterface is missing for bridged network mode",
                    to: next
                )
            }
            next.bridgedInterface = bridgedInterface
        }
        return next
    }
}
