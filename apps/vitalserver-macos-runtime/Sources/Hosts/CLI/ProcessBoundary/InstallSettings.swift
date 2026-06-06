import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import InboundAdapters
import Errors

extension RuntimeInstallSettings {
    static var defaultSettingsPath: String {
        Constants.InstallPaths.settingsPath
    }

    static var defaultProxyPort: Int {
        Constants.Guest.publicPort
    }

    init(vitalFilesDirectory: String) {
        self.init(vitalFilesDirectory: vitalFilesDirectory, defaults: .hostCLI)
    }

    static func load(
        path: String = defaultSettingsPath,
        defaultVitalFilesDirectory: String,
        fileStore: RuntimeFileReading
    ) throws -> RuntimeInstallSettings {
        do {
            return try InboundAdapters.RuntimeInstallSettings.load(
                path: path,
                defaultVitalFilesDirectory: defaultVitalFilesDirectory,
                fileStore: fileStore,
                defaults: .hostCLI
            )
        } catch RuntimeInstallSettingsError.missingArgument(let message) {
            throw LauncherError.missingArgument(message)
        }
    }
}

extension RuntimeInstallSettingsDefaults {
    static var hostCLI: RuntimeInstallSettingsDefaults {
        let processorCount = ProcessInfo.processInfo.processorCount
        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        return RuntimeInstallSettingsDefaults(
            cpuCount: 8,
            memoryGiB: Constants.Defaults.defaultMemoryGiB(physicalMemoryBytes: physicalMemoryBytes),
            diskGiB: Constants.Defaults.defaultDiskGiB,
            networkMode: .shared,
            proxyPort: Constants.Guest.publicPort,
            adminPassword: Constants.Guest.defaultAdminPassword,
            vmHostname: Constants.Guest.hostname,
            publicPort: Constants.Guest.publicPort,
            minimumCPUCount: Constants.Defaults.minimumCPUCount,
            maximumAllowedCPUCount: Constants.Defaults.maximumAllowedCPUCount(systemCPUCount: processorCount),
            minimumMemoryGiB: Constants.Defaults.minimumMemoryGiB,
            maximumAllowedMemoryGiB: Constants.Defaults.maximumAllowedMemoryGiB(physicalMemoryBytes: physicalMemoryBytes),
            memoryStepGiB: Constants.Defaults.memoryStepGiB,
            minimumDiskGiB: Constants.Defaults.minimumDiskGiB,
            maximumDiskGiB: Constants.Defaults.maximumDiskGiB,
            diskStepGiB: Constants.Defaults.diskStepGiB
        )
    }
}
