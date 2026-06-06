import Application
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
import Errors

public enum VMRuntimeConfigComposition {
    public static func defaultConfig(paths: InstalledRuntimePaths) -> VMRuntimeConfig {
        var config = VMRuntimeConfig(
            cpuCount: min(
                max(ProcessInfo.processInfo.processorCount / 2, Constants.Defaults.minimumCPUCount),
                Constants.Defaults.maximumAllowedCPUCount
            ),
            memoryMiB: Constants.Defaults.memoryMiB,
            kernelPath: paths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.kernel).path,
            initialRamdiskPath: paths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.initialRamdisk).path,
            diskPath: paths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk).path,
            cloudInitPath: paths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.cloudInit).path,
            kernelCommandLine: Constants.BootAssets.commandLine,
            network: NetworkConfig(
                mode: .shared,
                bridgedInterface: nil,
                macAddress: nil
            ),
            sharedDirectory: SharedDirectoryConfig(
                hostPath: paths.dataDirectory.path,
                tag: Constants.Defaults.sharedDirectoryTag,
                guestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
                readOnly: false
            ),
            vitalFilesDirectory: SharedDirectoryConfig(
                hostPath: paths.vitalFilesDirectory.path,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            ),
            autoRecoveryEnabled: true,
            preventSystemSleep: true,
            sshAuthorizedKeys: []
        )
        ensureNetworkIdentity(&config)
        return config
    }

    public static func load(from url: URL, fileStore: RuntimeFileReading) throws -> VMRuntimeConfig {
        do {
            return try VMRuntimeConfig.readDocument(from: url, fileStore: fileStore)
        } catch VMRuntimeConfigReadError.missingConfig {
            throw LauncherError.missingConfig(url)
        }
    }

    public static func validateBootFiles(_ config: VMRuntimeConfig, fileStore: RuntimeFileReading) throws {
        do {
            try VMRuntimeConfig.validateBootFilePaths(config, fileStore: fileStore)
        } catch VMRuntimeBootFileValidationError.missingFile(let path) {
            throw LauncherError.missingFile(path)
        }
    }

    public static func ensureNetworkIdentity(_ config: inout VMRuntimeConfig) {
        VMRuntimeConfig.ensureNetworkIdentity(
            &config,
            localMacPrefix0: Constants.Network.localMacPrefix0
        )
    }

    public static func ensureRuntimeDefaults(_ config: inout VMRuntimeConfig, paths: InstalledRuntimePaths) {
        ensureNetworkIdentity(&config)
        if config.cloudInitPath == nil || config.cloudInitPath?.isEmpty == true {
            config.cloudInitPath = paths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.cloudInit).path
        }
        if config.vitalFilesDirectory == nil {
            config.vitalFilesDirectory = SharedDirectoryConfig(
                hostPath: paths.vitalFilesDirectory.path,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            )
        }
        if config.autoRecoveryEnabled == nil {
            config.autoRecoveryEnabled = true
        }
        if config.preventSystemSleep == nil {
            config.preventSystemSleep = true
        }
        if config.sshAuthorizedKeys == nil {
            config.sshAuthorizedKeys = []
        }
    }

    public static func prettyJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
