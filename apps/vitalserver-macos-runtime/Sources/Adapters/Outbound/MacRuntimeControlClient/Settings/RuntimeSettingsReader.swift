import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeSettingsReading: Sendable {
    func load() -> RuntimeSettings
}

struct RuntimeSettingsPaths {
    var vmConfig = InstalledRuntimePaths.defaultInstalled.vmConfig.path
    var appliedVMConfig = InstalledRuntimePaths.defaultInstalled.appliedVMConfig.path
    var vmDisk = InstalledRuntimePaths.defaultInstalled.vmDisk.path
    var guestRuntimeSettings = InstalledRuntimePaths.defaultInstalled.guestRuntimeSettings.path
    var runtimeControlSettings = InstalledRuntimePaths.defaultInstalled.runtimeControlSettings.path
    var proxyLaunchDaemon = InstalledRuntimePaths.defaultInstalled.proxyLaunchDaemon.path

    init(
        vmConfig: String = InstalledRuntimePaths.defaultInstalled.vmConfig.path,
        appliedVMConfig: String = InstalledRuntimePaths.defaultInstalled.appliedVMConfig.path,
        vmDisk: String = InstalledRuntimePaths.defaultInstalled.vmDisk.path,
        guestRuntimeSettings: String = InstalledRuntimePaths.defaultInstalled.guestRuntimeSettings.path,
        runtimeControlSettings: String = InstalledRuntimePaths.defaultInstalled.runtimeControlSettings.path,
        proxyLaunchDaemon: String = InstalledRuntimePaths.defaultInstalled.proxyLaunchDaemon.path
    ) {
        self.vmConfig = vmConfig
        self.appliedVMConfig = appliedVMConfig
        self.vmDisk = vmDisk
        self.guestRuntimeSettings = guestRuntimeSettings
        self.runtimeControlSettings = runtimeControlSettings
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
            appliedVMConfig: VMConfigDocument.loadResult(path: paths.appliedVMConfig, fileStore: fileStore),
            diskGiB: diskSizeGiB(path: paths.vmDisk),
            guestRuntimeSettings: GuestRuntimeSettings.loadResult(
                path: paths.guestRuntimeSettings,
                fileStore: fileStore
            ),
            logArchiveSettings: RuntimeControlSettingsDocument.loadResult(
                path: paths.runtimeControlSettings,
                fileStore: fileStore
            ),
            proxyPort: RuntimeProxyLaunchDaemonPortReader(
                plistPath: paths.proxyLaunchDaemon,
                fileStore: fileStore
            ).loadSettingsResult(),
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

}
