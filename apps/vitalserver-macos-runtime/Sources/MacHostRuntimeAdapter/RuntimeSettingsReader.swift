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
    private var runCommand: @Sendable (String, [String]) -> RuntimeCommandResult

    init(
        paths: RuntimeSettingsPaths = RuntimeSettingsPaths(),
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        runCommand: @escaping @Sendable (String, [String]) -> RuntimeCommandResult = ProcessRunner.runSync
    ) {
        self.paths = paths
        self.fileStore = fileStore
        self.runCommand = runCommand
    }

    func load() -> RuntimeSettings {
        var settings = RuntimeSettings()

        switch VMConfigDocument.loadResult(path: paths.vmConfig, fileStore: fileStore) {
        case .loaded(let vmConfig):
            settings.cpuCount = vmConfig.cpuCount
            settings.memoryGiB = max(Int(vmConfig.memoryMiB / 1024), 1)
            applyNetworkSettings(vmConfig.network, to: &settings)
            if let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath {
                settings.vitalFilesDirectory = vitalFilesDirectory
            }
            if let autoRecoveryEnabled = vmConfig.autoRecoveryEnabled {
                settings.autoRecoveryEnabled = autoRecoveryEnabled
            } else {
                settings.readIssues.append(RuntimeSettingsReadIssue(
                    source: "vmConfig.autoRecoveryEnabled",
                    message: "autoRecoveryEnabled is missing"
                ))
            }
            if let preventSystemSleep = vmConfig.preventSystemSleep {
                settings.preventSystemSleep = preventSystemSleep
            } else {
                settings.readIssues.append(RuntimeSettingsReadIssue(
                    source: "vmConfig.preventSystemSleep",
                    message: "preventSystemSleep is missing"
                ))
            }
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

        switch startOnBootEnabled() {
        case .loaded(let startOnBoot):
            settings.startOnBoot = startOnBoot
            settings.startOnBootConfigurable = true
        case .missing:
            settings.startOnBootConfigurable = false
        case .failed(let message):
            settings.startOnBootConfigurable = false
            settings.readIssues.append(RuntimeSettingsReadIssue(source: "startOnBoot", message: message))
        }
        return settings
    }

    private func loadLegacyGuestRuntimeConfig(into settings: inout RuntimeSettings) {
        switch LegacyGuestRuntimeSettings.loadResult(path: paths.guestRuntimeConfig, fileStore: fileStore) {
        case .loaded(let guestConfig):
            applyLegacy(guestConfig, to: &settings)
        case .missing:
            break
        case .failed(let message):
            if !LegacyGuestRuntimeSettings.isPermissionDenied(message) {
                settings.readIssues.append(RuntimeSettingsReadIssue(source: "guestRuntimeConfig", message: message))
            }
        }
    }

    private func apply(_ guestSettings: GuestRuntimeSettings, to settings: inout RuntimeSettings) {
        settings.vitalServerURL = guestSettings.vitalServerURL
        settings.remoteConsoleURL = guestSettings.remoteConsoleURL
        settings.publicHost = guestSettings.publicHost
        settings.publicPort = guestSettings.publicPort
        settings.redisBackupRetentionCount = min(max(guestSettings.redisBackupRetentionCount, 1), 30)
    }

    private func applyLegacy(_ guestSettings: LegacyGuestRuntimeSettings, to settings: inout RuntimeSettings) {
        let publicHost = guestSettings.publicHost ?? ""
        let publicPort = guestSettings.publicPort ?? RuntimeSettings().publicPort
        settings.vitalServerURL = guestSettings.vitalServerURL
            ?? Self.migrateLegacyVitalServerURL(publicHost: publicHost, publicPort: publicPort)
        settings.remoteConsoleURL = guestSettings.remoteConsoleURL ?? ""
        settings.publicHost = publicHost
        settings.publicPort = publicPort
        if let redisBackupRetentionCount = guestSettings.redisBackupRetentionCount {
            settings.redisBackupRetentionCount = min(max(redisBackupRetentionCount, 1), 30)
        }
    }

    private static func migrateLegacyVitalServerURL(publicHost: String, publicPort: Int) -> String {
        guard !publicHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return "http://\(publicHost):\(publicPort)/"
    }

    private func applyNetworkSettings(_ network: NetworkDocument, to settings: inout RuntimeSettings) {
        guard let networkMode = RuntimeNetworkMode(rawValue: network.mode) else {
            settings.readIssues.append(RuntimeSettingsReadIssue(
                source: "vmConfig.network.mode",
                message: "network mode is invalid: \(network.mode)"
            ))
            return
        }

        settings.networkMode = networkMode
        switch networkMode {
        case .shared:
            settings.bridgedInterface = network.bridgedInterface ?? ""
        case .bridged:
            guard let bridgedInterface = network.bridgedInterface, !bridgedInterface.isEmpty else {
                settings.readIssues.append(RuntimeSettingsReadIssue(
                    source: "vmConfig.network.bridgedInterface",
                    message: "bridgedInterface is missing for bridged network mode"
                ))
                return
            }
            settings.bridgedInterface = bridgedInterface
        }
    }

    private func startOnBootEnabled() -> RuntimeSettingsLoadResult<Bool> {
        let result = runCommand(
            RuntimeAdapterConstants.Commands.launchctl,
            ["print-disabled", "system"]
        )
        guard result.exitCode == 0 else {
            return .failed(result.stderr.isEmpty ? "launchctl print-disabled failed" : result.stderr)
        }
        let output = result.stdout
        for label in [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
        ] where output.contains("\"\(label)\" => true") {
            return .loaded(false)
        }
        return .loaded(true)
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
    let vitalServerURL: String
    let remoteConsoleURL: String
    let publicHost: String
    let publicPort: Int
    let redisBackupRetentionCount: Int

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

private struct LegacyGuestRuntimeSettings: Decodable {
    let vitalServerURL: String?
    let remoteConsoleURL: String?
    let publicHost: String?
    let publicPort: Int?
    let redisBackupRetentionCount: Int?

    static func loadResult(path: String, fileStore: RuntimeFileReading) -> RuntimeSettingsLoadResult<LegacyGuestRuntimeSettings> {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(LegacyGuestRuntimeSettings.self, from: data))
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
