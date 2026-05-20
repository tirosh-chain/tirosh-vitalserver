import Foundation

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

    // The default boot asset names match the Linux kernel/initrd style used by
    // Apple's Linux VM sample and keep the first PoC explicit.
    static func `default`(home: URL) -> VMRuntimeConfig {
        let runtime = home.appendingPathComponent(Constants.Paths.runtimeDirectory)
        let sharedData = home.appendingPathComponent(Constants.Paths.dataDirectory)
        return VMRuntimeConfig(
            cpuCount: min(
                max(ProcessInfo.processInfo.processorCount / 2, Constants.Defaults.minimumCPUCount),
                Constants.Defaults.maximumCPUCount
            ),
            memoryMiB: Constants.Defaults.memoryMiB,
            kernelPath: runtime.appendingPathComponent(Constants.BootAssets.kernel).path,
            initialRamdiskPath: runtime.appendingPathComponent(Constants.BootAssets.initialRamdisk).path,
            diskPath: runtime.appendingPathComponent(Constants.BootAssets.disk).path,
            cloudInitPath: runtime.appendingPathComponent(Constants.BootAssets.cloudInit).path,
            kernelCommandLine: Constants.BootAssets.commandLine,
            network: NetworkConfig(
                mode: .shared,
                bridgedInterface: nil,
                macAddress: Self.generateMacAddress()
            ),
            sharedDirectory: SharedDirectoryConfig(
                hostPath: sharedData.path,
                tag: Constants.Defaults.sharedDirectoryTag,
                guestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
                readOnly: false
            ),
            vitalFilesDirectory: SharedDirectoryConfig(
                hostPath: sharedData.appendingPathComponent(Constants.Paths.vitalFilesDirectory).path,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            )
        )
    }

    static func load(from url: URL) throws -> VMRuntimeConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LauncherError.missingConfig(url)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VMRuntimeConfig.self, from: data)
    }

    // Validate before touching Virtualization.framework so errors stay readable.
    static func validateBootFiles(_ config: VMRuntimeConfig) throws {
        let fileManager = FileManager.default
        for path in [config.kernelPath, config.initialRamdiskPath, config.diskPath].compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: path) else {
                throw LauncherError.missingFile(path)
            }
        }
    }

    static func ensureNetworkIdentity(_ config: inout VMRuntimeConfig) {
        if config.network.macAddress == nil || config.network.macAddress?.isEmpty == true {
            config.network.macAddress = generateMacAddress()
        }
    }

    static func ensureRuntimeDefaults(_ config: inout VMRuntimeConfig, home: URL) {
        ensureNetworkIdentity(&config)
        if config.cloudInitPath == nil || config.cloudInitPath?.isEmpty == true {
            config.cloudInitPath = home
                .appendingPathComponent(Constants.Paths.runtimeDirectory)
                .appendingPathComponent(Constants.BootAssets.cloudInit)
                .path
        }
        if config.vitalFilesDirectory == nil {
            config.vitalFilesDirectory = SharedDirectoryConfig(
                hostPath: home
                    .appendingPathComponent(Constants.Paths.dataDirectory)
                    .appendingPathComponent(Constants.Paths.vitalFilesDirectory)
                    .path,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            )
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
