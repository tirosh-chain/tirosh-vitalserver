import Contracts

public extension RuntimePlatformSettingsRead {
    init(runtimeSettings settings: RuntimeSettings) {
        let issues = settings.readIssues.map {
            RuntimePlatformSettingsReadIssue(source: $0.source, message: $0.message)
        }
        self.init(
            state: issues.isEmpty ? .loaded : .failed,
            settings: issues.isEmpty ? RuntimePlatformSettingsDocument(runtimeSettings: settings) : nil,
            readIssues: issues,
            readError: issues.isEmpty
                ? nil
                : "Platform settings owner reported \(issues.count) read issue(s); apply is unavailable."
        )
    }
}

public extension RuntimePlatformSettingsDocument {
    init(runtimeSettings settings: RuntimeSettings) {
        self.init(
            cpuCount: settings.cpuCount,
            memoryGiB: settings.memoryGiB,
            diskGiB: settings.diskGiB,
            minimumDiskGiB: settings.minimumDiskGiB,
            networkMode: settings.networkMode == .shared ? .shared : .bridged,
            bridgedInterface: settings.bridgedInterface,
            proxyPort: settings.proxyPort,
            runtimeControlPort: settings.runtimeControlPort,
            vitalFilesDirectory: settings.vitalFilesDirectory,
            startOnBoot: settings.startOnBoot,
            startOnBootConfigurable: settings.startOnBootConfigurable,
            autoRecoveryEnabled: settings.autoRecoveryEnabled,
            preventSystemSleep: settings.preventSystemSleep,
            automaticBackupEnabled: settings.automaticBackupEnabled,
            backupScheduleTimes: settings.backupScheduleTimes,
            backupRetentionCount: settings.backupRetentionCount,
            logArchiveRetentionDays: settings.logArchiveRetentionDays,
            logArchiveMaximumGiB: settings.logArchiveMaximumGiB,
            restartAfterSave: settings.restartAfterSave
        )
    }
}

public extension RuntimePlatformSettingsApplyDocument {
    func applying(to current: RuntimeSettings) -> RuntimeSettings {
        var settings = current
        settings.cpuCount = cpuCount
        settings.memoryGiB = memoryGiB
        settings.diskGiB = diskGiB
        settings.networkMode = networkMode == .shared ? .shared : .bridged
        settings.bridgedInterface = bridgedInterface
        settings.proxyPort = proxyPort
        settings.runtimeControlPort = runtimeControlPort
        settings.vitalFilesDirectory = vitalFilesDirectory
        settings.startOnBoot = startOnBoot
        settings.autoRecoveryEnabled = autoRecoveryEnabled
        settings.preventSystemSleep = preventSystemSleep
        settings.automaticBackupEnabled = automaticBackupEnabled
        settings.backupScheduleTimes = backupScheduleTimes
        settings.backupRetentionCount = backupRetentionCount
        settings.logArchiveRetentionDays = logArchiveRetentionDays
        settings.logArchiveMaximumGiB = logArchiveMaximumGiB
        settings.restartAfterSave = restartAfterSave
        return settings
    }
}
