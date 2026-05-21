import Foundation

struct RuntimeSettings: Codable {
    var cpuCount = 8
    var memoryGiB = 8
    var diskGiB = AppConstants.SettingsLimits.defaultDiskGiB
    var minimumDiskGiB = AppConstants.SettingsLimits.minimumDiskGiB
    var networkMode = AppConstants.Values.networkShared
    var bridgedInterface = ""
    var proxyPort = AppConstants.Product.defaultProxyPort
    var vitalFilesDirectory = AppConstants.Paths.vitalFiles
    var publicHost = ""
    var publicPort = 80
    var adminPassword = ""
    var changeAdminPassword = false
    var startOnBoot = true
    var startOnBootConfigurable = true
    var restartAfterSave = true

    @MainActor
    static func load() -> RuntimeSettings {
        SystemRuntimeSettingsReader().load()
    }

    func configureArguments(adminPasswordFile: String? = nil) -> [String] {
        var arguments = [
            AppConstants.RuntimeCommand.runtime,
            AppConstants.RuntimeCommand.configure,
            AppConstants.RuntimeCommand.optionCPU,
            String(cpuCount),
            AppConstants.RuntimeCommand.optionMemoryGiB,
            String(memoryGiB),
            AppConstants.RuntimeCommand.optionDiskGiB,
            String(diskGiB),
            AppConstants.RuntimeCommand.optionNetwork,
            networkMode,
            AppConstants.RuntimeCommand.optionProxyPort,
            String(proxyPort),
            AppConstants.RuntimeCommand.optionVitalFilesDirectory,
            vitalFilesDirectory,
            AppConstants.RuntimeCommand.optionPublicHost,
            publicHost,
            AppConstants.RuntimeCommand.optionPublicPort,
            String(publicPort),
        ]
        if startOnBootConfigurable {
            arguments += [
                AppConstants.RuntimeCommand.optionStartOnBoot,
                startOnBoot ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse,
            ]
        }
        if networkMode == AppConstants.Values.networkBridged, !bridgedInterface.isEmpty {
            arguments += [AppConstants.RuntimeCommand.optionBridgedInterface, bridgedInterface]
        }
        if let adminPasswordFile {
            arguments += [AppConstants.RuntimeCommand.optionAdminPasswordFile, adminPasswordFile]
        }
        if restartAfterSave {
            arguments.append(AppConstants.RuntimeCommand.optionRestart)
        }
        return arguments
    }

}
