import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
import Errors

public enum VMRuntimeConfigComposition {
    public static func defaultConfig(
        paths: InstalledRuntimePaths,
        processorCount: Int,
        physicalMemoryBytes: UInt64
    ) -> VMRuntimeConfig {
        var config = VMRuntimeConfig(
            cpuCount: min(
                max(processorCount / 2, Constants.Defaults.minimumCPUCount),
                Constants.Defaults.maximumAllowedCPUCount(systemCPUCount: processorCount)
            ),
            memoryMiB: Constants.Defaults.memoryMiB(physicalMemoryBytes: physicalMemoryBytes),
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
        } catch VMRuntimeConfigReadError.configInspectionFailed(let path, let reason) {
            throw LauncherError.runtimeOperationFailed(
                "VM config path inspection failed path=\(path) reason=\(reason)"
            )
        } catch VMRuntimeConfigReadError.unexpectedConfigPathState(let path, let state) {
            throw LauncherError.runtimeOperationFailed(
                "VM config path state is unexpected path=\(path) state=\(state)"
            )
        }
    }

    public static func validateBootFiles(_ config: VMRuntimeConfig, fileStore: RuntimeFileReading) throws {
        do {
            try VMRuntimeConfig.validateBootFilePaths(config, fileStore: fileStore)
        } catch VMRuntimeBootFileValidationError.missingFile(let path) {
            throw LauncherError.missingFile(path)
        } catch VMRuntimeBootFileValidationError.pathInspectionFailed(let path, let reason) {
            throw LauncherError.runtimeOperationFailed(
                "VM boot file path inspection failed path=\(path) reason=\(reason)"
            )
        } catch VMRuntimeBootFileValidationError.unexpectedPathState(let path, let state) {
            throw LauncherError.runtimeOperationFailed(
                "VM boot file path state is unexpected path=\(path) state=\(state)"
            )
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
        removeUnsupportedKernelCommandLineGuards(&config)
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

    private static func removeUnsupportedKernelCommandLineGuards(_ config: inout VMRuntimeConfig) {
        let tokens = config.kernelCommandLine
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.hasPrefix("bpf_jit_enable=") }
        config.kernelCommandLine = tokens.joined(separator: " ")
    }

    public static func prettyJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
