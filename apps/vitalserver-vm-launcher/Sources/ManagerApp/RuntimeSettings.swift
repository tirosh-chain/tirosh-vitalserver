import Foundation

struct RuntimeSettings: Codable {
    var cpuCount = 8
    var memoryGiB = 8
    var diskGiB = 64
    var minimumDiskGiB = 4
    var networkMode = AppConstants.Values.networkShared
    var bridgedInterface = ""
    var proxyPort = AppConstants.Product.defaultProxyPort
    var vitalFilesDirectory = "\(AppConstants.Paths.vmHome)/data/vital-files"
    var publicHost = ""
    var publicPort = 80
    var adminPassword = ""
    var changeAdminPassword = false
    var startOnBoot = true
    var startOnBootConfigurable = true
    var restartAfterSave = true

    static func load() -> RuntimeSettings {
        loadInstalled()
    }

    private static func loadInstalled() -> RuntimeSettings {
        var settings = RuntimeSettings()

        if let vmConfig = VMConfigDocument.load(path: AppConstants.Paths.vmConfig) {
            settings.cpuCount = vmConfig.cpuCount
            settings.memoryGiB = max(Int(vmConfig.memoryMiB / 1024), 1)
            settings.networkMode = AppConstants.Values.networkShared
            settings.bridgedInterface = vmConfig.network.bridgedInterface ?? ""
            if let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath {
                settings.vitalFilesDirectory = vitalFilesDirectory
            }
        }

        if let diskGiB = diskSizeGiB(path: AppConstants.Paths.vmDisk) {
            settings.diskGiB = diskGiB
            settings.minimumDiskGiB = diskGiB
        }
        if let guestConfig = GuestRuntimeConfig.load(path: AppConstants.Paths.guestRuntimeConfig) {
            settings.publicHost = guestConfig.publicHost
            settings.publicPort = guestConfig.publicPort
        }

        settings.proxyPort = RuntimeStatus.load(paths: RuntimePaths()).proxyPort
        if let startOnBoot = startOnBootEnabled() {
            settings.startOnBoot = startOnBoot
            settings.startOnBootConfigurable = true
        } else {
            settings.startOnBootConfigurable = false
        }
        return settings
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

    private static func startOnBootEnabled() -> Bool? {
        let result = ProcessRunner.runSync(
            AppConstants.Commands.launchctl,
            arguments: ["print-disabled", "system"]
        )
        guard result.exitCode == 0 else {
            return nil
        }
        let output = result.stdout
        for label in [
            AppConstants.Launchd.vmService,
            AppConstants.Launchd.proxyService,
            AppConstants.Launchd.watchdogService,
        ] where output.contains("\"\(label)\" => true") {
            return false
        }
        return true
    }

    private static func diskSizeGiB(path: String) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        let bytesPerGiB = 1024 * 1024 * 1024
        return max(Int((size.int64Value + Int64(bytesPerGiB - 1)) / Int64(bytesPerGiB)), 1)
    }
}

private struct VMConfigDocument: Decodable {
    let cpuCount: Int
    let memoryMiB: UInt64
    let network: NetworkDocument
    let vitalFilesDirectory: SharedDirectoryDocument?

    static func load(path: String) -> VMConfigDocument? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(VMConfigDocument.self, from: data)
    }
}

private struct NetworkDocument: Decodable {
    let mode: String
    let bridgedInterface: String?
}

private struct SharedDirectoryDocument: Decodable {
    let hostPath: String
}

private struct GuestRuntimeConfig: Decodable {
    let publicHost: String
    let publicPort: Int

    static func load(path: String) -> GuestRuntimeConfig? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeConfig.self, from: data)
    }
}
