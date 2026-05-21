import Foundation

@MainActor
protocol RuntimeSettingsReading {
    func load() -> RuntimeSettings
}

struct RuntimeSettingsPaths {
    var vmConfig = AppConstants.Paths.vmConfig
    var vmDisk = AppConstants.Paths.vmDisk
    var guestRuntimeConfig = AppConstants.Paths.guestRuntimeConfig
}

@MainActor
struct SystemRuntimeSettingsReader: RuntimeSettingsReading {
    var paths = RuntimeSettingsPaths()
    var statusReader = SystemRuntimeStatusReader(paths: RuntimePaths())

    func load() -> RuntimeSettings {
        var settings = RuntimeSettings()

        if let vmConfig = VMConfigDocument.load(path: paths.vmConfig) {
            settings.cpuCount = vmConfig.cpuCount
            settings.memoryGiB = max(Int(vmConfig.memoryMiB / 1024), 1)
            settings.networkMode = AppConstants.Values.networkShared
            settings.bridgedInterface = vmConfig.network.bridgedInterface ?? ""
            if let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath {
                settings.vitalFilesDirectory = vitalFilesDirectory
            }
        }

        if let diskGiB = diskSizeGiB(path: paths.vmDisk) {
            settings.diskGiB = diskGiB
            settings.minimumDiskGiB = diskGiB
        }
        if let guestConfig = GuestRuntimeConfig.load(path: paths.guestRuntimeConfig) {
            settings.publicHost = guestConfig.publicHost
            settings.publicPort = guestConfig.publicPort
        }

        settings.proxyPort = statusReader.loadBaseStatus().proxyPort
        if let startOnBoot = startOnBootEnabled() {
            settings.startOnBoot = startOnBoot
            settings.startOnBootConfigurable = true
        } else {
            settings.startOnBootConfigurable = false
        }
        return settings
    }

    private func startOnBootEnabled() -> Bool? {
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

    private func diskSizeGiB(path: String) -> Int? {
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
