import Foundation
import RuntimeControl
import RuntimeCore
import HostRuntimeInfrastructure

@MainActor
public protocol RuntimeSettingsReading {
    func load() -> RuntimeSettings
}

public struct RuntimeSettingsPaths {
    public var vmConfig = RuntimeAdapterConstants.Paths.vmConfig
    public var vmDisk = RuntimeAdapterConstants.Paths.vmDisk
    public var guestRuntimeConfig = RuntimeAdapterConstants.Paths.guestRuntimeConfig

    public init(
        vmConfig: String = RuntimeAdapterConstants.Paths.vmConfig,
        vmDisk: String = RuntimeAdapterConstants.Paths.vmDisk,
        guestRuntimeConfig: String = RuntimeAdapterConstants.Paths.guestRuntimeConfig
    ) {
        self.vmConfig = vmConfig
        self.vmDisk = vmDisk
        self.guestRuntimeConfig = guestRuntimeConfig
    }
}

@MainActor
public struct SystemRuntimeSettingsReader: RuntimeSettingsReading {
    public var paths = RuntimeSettingsPaths()
    public var statusReader = SystemRuntimeStatusReader(paths: RuntimePaths())
    private var fileStore: RuntimeFileStore = LocalRuntimeFileStore()

    public init(
        paths: RuntimeSettingsPaths = RuntimeSettingsPaths(),
        statusReader: SystemRuntimeStatusReader? = nil,
        fileStore: RuntimeFileStore = LocalRuntimeFileStore()
    ) {
        self.paths = paths
        self.statusReader = statusReader ?? SystemRuntimeStatusReader(paths: RuntimePaths(), fileStore: fileStore)
        self.fileStore = fileStore
    }

    public func load() -> RuntimeSettings {
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
        }

        if let diskGiB = diskSizeGiB(path: paths.vmDisk) {
            settings.diskGiB = diskGiB
            settings.minimumDiskGiB = diskGiB
        }
        if let guestConfig = GuestRuntimeConfig.load(path: paths.guestRuntimeConfig, fileStore: fileStore) {
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
}

private struct VMConfigDocument: Decodable {
    let cpuCount: Int
    let memoryMiB: UInt64
    let network: NetworkDocument
    let vitalFilesDirectory: SharedDirectoryDocument?
    let autoRecoveryEnabled: Bool?

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

    static func load(path: String, fileStore: RuntimeFileReading) -> GuestRuntimeConfig? {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeConfig.self, from: data)
    }
}
