import Foundation
import RuntimeCore
import RuntimeInfrastructure

struct VMRuntimeConfig: Codable {
    var cpuCount: Int
    var memoryMiB: UInt64
    var kernelPath: String
    var initialRamdiskPath: String?
    var diskPath: String?
    var cloudInitPath: String?
    var kernelCommandLine: String
    var network: NetworkConfig
    var sharedDirectory: SharedDirectoryConfig?
    var vitalFilesDirectory: SharedDirectoryConfig?
    var autoRecoveryEnabled: Bool? = nil

    // The default boot asset names match the Linux kernel/initrd style used by
    // Apple's Linux VM sample and keep the first PoC explicit.
    static func `default`(paths: InstalledRuntimePaths) -> VMRuntimeConfig {
        return VMRuntimeConfig(
            cpuCount: min(
                max(ProcessInfo.processInfo.processorCount / 2, Constants.Defaults.minimumCPUCount),
                Constants.Defaults.maximumCPUCount
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
                macAddress: Self.generateMacAddress()
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
            autoRecoveryEnabled: true
        )
    }

    static func load(from url: URL, fileStore: RuntimeFileReading) throws -> VMRuntimeConfig {
        guard fileStore.fileExists(url) else {
            throw LauncherError.missingConfig(url)
        }
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(VMRuntimeConfig.self, from: data)
    }

    // Validate before touching Virtualization.framework so errors stay readable.
    static func validateBootFiles(_ config: VMRuntimeConfig, fileStore: RuntimeFileReading) throws {
        for path in [config.kernelPath, config.initialRamdiskPath, config.diskPath].compactMap({ $0 }) {
            guard fileStore.fileExists(URL(fileURLWithPath: path)) else {
                throw LauncherError.missingFile(path)
            }
        }
    }

    static func ensureNetworkIdentity(_ config: inout VMRuntimeConfig) {
        if config.network.macAddress == nil || config.network.macAddress?.isEmpty == true {
            config.network.macAddress = generateMacAddress()
        }
    }

    static func ensureRuntimeDefaults(_ config: inout VMRuntimeConfig, paths: InstalledRuntimePaths) {
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
    }

    private static func generateMacAddress() -> String {
        let bytes = [
            Constants.Network.localMacPrefix0,
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
        ]
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

struct NetworkConfig: Codable {
    var mode: NetworkMode
    var bridgedInterface: String?
    var macAddress: String?
}

struct SharedDirectoryConfig: Codable {
    var hostPath: String
    var tag: String
    var guestMountPath: String
    var readOnly: Bool
}

enum NetworkMode: String, Codable {
    case shared
    case bridged
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
