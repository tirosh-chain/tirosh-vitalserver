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
    var guestRuntimeSettings = RuntimeAdapterConstants.Paths.guestRuntimeSettings
    var guestRuntimeConfig = RuntimeAdapterConstants.Paths.guestRuntimeConfig
    var proxyLaunchDaemon = RuntimeAdapterConstants.Paths.proxyLaunchDaemon

    init(
        vmConfig: String = RuntimeAdapterConstants.Paths.vmConfig,
        vmDisk: String = RuntimeAdapterConstants.Paths.vmDisk,
        guestRuntimeSettings: String = RuntimeAdapterConstants.Paths.guestRuntimeSettings,
        guestRuntimeConfig: String = RuntimeAdapterConstants.Paths.guestRuntimeConfig,
        proxyLaunchDaemon: String = RuntimeAdapterConstants.Paths.proxyLaunchDaemon
    ) {
        self.vmConfig = vmConfig
        self.vmDisk = vmDisk
        self.guestRuntimeSettings = guestRuntimeSettings
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

        switch VMConfigDocument.loadResult(path: paths.vmConfig, fileStore: fileStore) {
        case .loaded(let vmConfig):
            settings.cpuCount = vmConfig.cpuCount
            settings.memoryGiB = max(Int(vmConfig.memoryMiB / 1024), 1)
            settings.networkMode = RuntimeNetworkMode.shared
            settings.bridgedInterface = vmConfig.network.bridgedInterface ?? ""
            if let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath {
                settings.vitalFilesDirectory = vitalFilesDirectory
            }
            settings.autoRecoveryEnabled = vmConfig.autoRecoveryEnabled ?? true
            settings.preventSystemSleep = vmConfig.preventSystemSleep ?? true
        case .missing:
            break
        case .failed(let message):
            settings.readIssues.append(RuntimeSettingsReadIssue(source: "vmConfig", message: message))
        }

        switch diskSizeGiB(path: paths.vmDisk) {
        case .loaded(let diskGiB):
            settings.diskGiB = diskGiB
            settings.minimumDiskGiB = diskGiB
        case .missing:
            break
        case .failed(let message):
            settings.readIssues.append(RuntimeSettingsReadIssue(source: "vmDisk", message: message))
        }
        switch GuestRuntimeSettings.loadResult(path: paths.guestRuntimeSettings, fileStore: fileStore) {
        case .loaded(let guestSettings):
            apply(guestSettings, to: &settings)
        case .missing:
            loadLegacyGuestRuntimeConfig(into: &settings)
        case .failed(let message):
            settings.readIssues.append(RuntimeSettingsReadIssue(source: "guestRuntimeSettings", message: message))
            loadLegacyGuestRuntimeConfig(into: &settings)
        }
        switch proxyPort(plistPath: paths.proxyLaunchDaemon) {
        case .loaded(let proxyPort):
            settings.proxyPort = proxyPort
        case .missing:
            break
        case .failed(let message):
            settings.readIssues.append(RuntimeSettingsReadIssue(source: "proxyLaunchDaemon", message: message))
        }

        if let startOnBoot = startOnBootEnabled() {
            settings.startOnBoot = startOnBoot
            settings.startOnBootConfigurable = true
        } else {
            settings.startOnBootConfigurable = false
        }
        return settings
    }

    private func loadLegacyGuestRuntimeConfig(into settings: inout RuntimeSettings) {
        switch GuestRuntimeSettings.loadResult(path: paths.guestRuntimeConfig, fileStore: fileStore) {
        case .loaded(let guestConfig):
            apply(guestConfig, to: &settings)
        case .missing:
            break
        case .failed(let message):
            if !GuestRuntimeSettings.isPermissionDenied(message) {
                settings.readIssues.append(RuntimeSettingsReadIssue(source: "guestRuntimeConfig", message: message))
            }
        }
    }

    private func apply(_ guestSettings: GuestRuntimeSettings, to settings: inout RuntimeSettings) {
        settings.publicHost = guestSettings.publicHost
        settings.publicPort = guestSettings.publicPort
        if let redisBackupRetentionCount = guestSettings.redisBackupRetentionCount {
            settings.redisBackupRetentionCount = min(max(redisBackupRetentionCount, 1), 30)
        }
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

    private func diskSizeGiB(path: String) -> RuntimeSettingsLoadResult<Int> {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let size = try fileStore.fileSize(url)
            let bytesPerGiB = 1024 * 1024 * 1024
            return .loaded(max(Int((size + UInt64(bytesPerGiB - 1)) / UInt64(bytesPerGiB)), 1))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func proxyPort(plistPath: String) -> RuntimeSettingsLoadResult<Int> {
        let url = URL(fileURLWithPath: plistPath)
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            guard let document = plist as? [String: Any],
                  let environment = document["EnvironmentVariables"] as? [String: Any],
                  let rawPort = environment["VITALSERVER_PROXY_PORT"] as? String,
                  let port = Int(rawPort),
                  (1...65_535).contains(port)
            else {
                return .failed("VITALSERVER_PROXY_PORT is missing or invalid")
            }
            return .loaded(port)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private enum RuntimeSettingsLoadResult<T> {
    case missing
    case loaded(T)
    case failed(String)
}

private struct VMConfigDocument: Decodable {
    let cpuCount: Int
    let memoryMiB: UInt64
    let network: NetworkDocument
    let vitalFilesDirectory: SharedDirectoryDocument?
    let autoRecoveryEnabled: Bool?
    let preventSystemSleep: Bool?

    static func loadResult(path: String, fileStore: RuntimeFileReading) -> RuntimeSettingsLoadResult<VMConfigDocument> {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(VMConfigDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private struct NetworkDocument: Decodable {
    let mode: String
    let bridgedInterface: String?
}

private struct SharedDirectoryDocument: Decodable {
    let hostPath: String
}

private struct GuestRuntimeSettings: Decodable {
    let publicHost: String
    let publicPort: Int
    let redisBackupRetentionCount: Int?

    static func loadResult(path: String, fileStore: RuntimeFileReading) -> RuntimeSettingsLoadResult<GuestRuntimeSettings> {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(GuestRuntimeSettings.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func isPermissionDenied(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("permission")
            || normalized.contains("not permitted")
            || normalized.contains("operation not permitted")
    }
}
