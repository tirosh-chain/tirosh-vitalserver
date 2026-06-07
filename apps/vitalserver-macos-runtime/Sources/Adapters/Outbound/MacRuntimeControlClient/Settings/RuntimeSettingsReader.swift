import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeSettingsReading: Sendable {
    func load() -> RuntimeSettings
}

struct RuntimeSettingsPaths {
    var vmConfig = RuntimeControlClientConstants.Paths.vmConfig
    var vmDisk = RuntimeControlClientConstants.Paths.vmDisk
    var guestRuntimeSettings = RuntimeControlClientConstants.Paths.guestRuntimeSettings
    var proxyLaunchDaemon = RuntimeControlClientConstants.Paths.proxyLaunchDaemon

    init(
        vmConfig: String = RuntimeControlClientConstants.Paths.vmConfig,
        vmDisk: String = RuntimeControlClientConstants.Paths.vmDisk,
        guestRuntimeSettings: String = RuntimeControlClientConstants.Paths.guestRuntimeSettings,
        proxyLaunchDaemon: String = RuntimeControlClientConstants.Paths.proxyLaunchDaemon
    ) {
        self.vmConfig = vmConfig
        self.vmDisk = vmDisk
        self.guestRuntimeSettings = guestRuntimeSettings
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
        RuntimeSettingsReadPolicy.settings(from: loadSnapshot())
    }

    private func loadSnapshot() -> RuntimeSettingsReadSnapshot {
        RuntimeSettingsReadSnapshot(
            vmConfig: VMConfigDocument.loadResult(path: paths.vmConfig, fileStore: fileStore),
            diskGiB: diskSizeGiB(path: paths.vmDisk),
            guestRuntimeSettings: GuestRuntimeSettings.loadResult(
                path: paths.guestRuntimeSettings,
                fileStore: fileStore
            ),
            proxyPort: proxyPort(plistPath: paths.proxyLaunchDaemon),
            startOnBoot: RuntimeSettingsStartOnBootReader(runCommand: runCommand).startOnBootEnabled()
        )
    }

    private func diskSizeGiB(path: String) -> RuntimeSettingsReadResult<Int> {
        let url = URL(fileURLWithPath: path)
        switch runtimeSettingsReadableFileState(url, fileStore: fileStore) {
        case .loaded:
            break
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
        }
        do {
            let size = try fileStore.fileSize(url)
            let bytesPerGiB = 1024 * 1024 * 1024
            return .loaded(max(Int((size + UInt64(bytesPerGiB - 1)) / UInt64(bytesPerGiB)), 1))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func proxyPort(plistPath: String) -> RuntimeSettingsReadResult<Int> {
        let url = URL(fileURLWithPath: plistPath)
        switch runtimeSettingsReadableFileState(url, fileStore: fileStore) {
        case .loaded:
            break
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
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
