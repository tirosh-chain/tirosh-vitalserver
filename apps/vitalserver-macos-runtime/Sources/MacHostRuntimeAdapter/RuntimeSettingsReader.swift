import Foundation
import RuntimeControl
import Core
import Contracts
import HostInfrastructure

protocol RuntimeSettingsReading: Sendable {
    func load() -> RuntimeSettings
}

struct RuntimeSettingsPaths {
    var vmConfig = RuntimeAdapterConstants.Paths.vmConfig
    var vmDisk = RuntimeAdapterConstants.Paths.vmDisk
    var guestRuntimeConfig = RuntimeAdapterConstants.Paths.guestRuntimeConfig
    var proxyLaunchDaemon = RuntimeAdapterConstants.Paths.proxyLaunchDaemon

    init(
        vmConfig: String = RuntimeAdapterConstants.Paths.vmConfig,
        vmDisk: String = RuntimeAdapterConstants.Paths.vmDisk,
        guestRuntimeConfig: String = RuntimeAdapterConstants.Paths.guestRuntimeConfig,
        proxyLaunchDaemon: String = RuntimeAdapterConstants.Paths.proxyLaunchDaemon
    ) {
        self.vmConfig = vmConfig
        self.vmDisk = vmDisk
        self.guestRuntimeConfig = guestRuntimeConfig
        self.proxyLaunchDaemon = proxyLaunchDaemon
    }
}

struct SystemRuntimeSettingsReader: RuntimeSettingsReading, @unchecked Sendable {
    var paths = RuntimeSettingsPaths()
    private var fileStore: RuntimeFileStore = SystemRuntimeFileStore()

    init(
        paths: RuntimeSettingsPaths = RuntimeSettingsPaths(),
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) {
        self.paths = paths
        self.fileStore = fileStore
    }

    func load() -> RuntimeSettings {
        var settings = RuntimeSettings()

        if let vmConfig = VMConfigDocument.load(path: paths.vmConfig, fileStore: fileStore) {
            settings.cpuCount = vmConfig.cpuCount
            settings.memoryGiB = max(Int(vmConfig.memoryMiB / 1024), 1)
            settings.networkMode = RuntimeNetworkMode.shared
            settings.bridgedInterface = vmConfig.network.bridgedInterface ?? ""
            if let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath {
                settings.vitalFilesDirectory = vitalFilesDirectory
            }
            settings.autoRecoveryEnabled = vmConfig.autoRecoveryEnabled ?? true
            settings.preventSystemSleep = vmConfig.preventSystemSleep ?? true
        }

        if let diskGiB = diskSizeGiB(path: paths.vmDisk) {
            settings.diskGiB = diskGiB
            settings.minimumDiskGiB = diskGiB
        }
        if let guestConfig = GuestRuntimeConfig.load(path: paths.guestRuntimeConfig, fileStore: fileStore) {
            settings.publicHost = guestConfig.publicHost
            settings.publicPort = guestConfig.publicPort
            if let redisBackupRetentionCount = guestConfig.redisBackupRetentionCount {
                settings.redisBackupRetentionCount = min(max(redisBackupRetentionCount, 1), 30)
            }
        }
        if let proxyPort = proxyPort(plistPath: paths.proxyLaunchDaemon) {
            settings.proxyPort = proxyPort
        }

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
            RuntimeAdapterConstants.Commands.launchctl,
            arguments: ["print-disabled", "system"]
        )
        guard result.exitCode == 0 else {
            return nil
        }
        let output = result.stdout
        for label in [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
        ] where output.contains("\"\(label)\" => true") {
            return false
        }
        return true
    }

    private func diskSizeGiB(path: String) -> Int? {
        guard let size = try? fileStore.fileSize(URL(fileURLWithPath: path)) else {
            return nil
        }
        let bytesPerGiB = 1024 * 1024 * 1024
        return max(Int((size + UInt64(bytesPerGiB - 1)) / UInt64(bytesPerGiB)), 1)
    }

    private func proxyPort(plistPath: String) -> Int? {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let document = plist as? [String: Any],
              let environment = document["EnvironmentVariables"] as? [String: Any],
              let rawPort = environment["VITALSERVER_PROXY_PORT"] as? String,
              let port = Int(rawPort),
              (1...65_535).contains(port)
        else {
            return nil
        }
        return port
    }
}

private struct VMConfigDocument: Decodable {
    let cpuCount: Int
    let memoryMiB: UInt64
    let network: NetworkDocument
    let vitalFilesDirectory: SharedDirectoryDocument?
    let autoRecoveryEnabled: Bool?
    let preventSystemSleep: Bool?

    static func load(path: String, fileStore: RuntimeFileReading) -> VMConfigDocument? {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: path)) else {
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
    let redisBackupRetentionCount: Int?

    static func load(path: String, fileStore: RuntimeFileReading) -> GuestRuntimeConfig? {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeConfig.self, from: data)
    }
}
