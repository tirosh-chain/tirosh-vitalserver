import Foundation

struct VMRuntimeConfig: Codable {
    var cpuCount: Int
    var memoryMiB: UInt64
    var kernelPath: String
    var initialRamdiskPath: String?
    var diskPath: String?
    var kernelCommandLine: String
    var network: NetworkConfig
    var sharedDirectory: SharedDirectoryConfig?

    // The default boot asset names match the Linux kernel/initrd style used by
    // Apple's Linux VM sample and keep the first PoC explicit.
    static func `default`(home: URL) -> VMRuntimeConfig {
        let images = home.appendingPathComponent(Constants.Paths.imagesDirectory)
        let sharedData = home.appendingPathComponent(Constants.Paths.dataDirectory)
        return VMRuntimeConfig(
            cpuCount: min(
                max(ProcessInfo.processInfo.processorCount / 2, Constants.Defaults.minimumCPUCount),
                Constants.Defaults.maximumCPUCount
            ),
            memoryMiB: Constants.Defaults.memoryMiB,
            kernelPath: images.appendingPathComponent(Constants.BootAssets.kernel).path,
            initialRamdiskPath: images.appendingPathComponent(Constants.BootAssets.initialRamdisk).path,
            diskPath: images.appendingPathComponent(Constants.BootAssets.disk).path,
            kernelCommandLine: Constants.BootAssets.commandLine,
            network: NetworkConfig(mode: .shared, bridgedInterface: nil),
            sharedDirectory: SharedDirectoryConfig(
                hostPath: sharedData.path,
                tag: Constants.Defaults.sharedDirectoryTag,
                guestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
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
}

struct NetworkConfig: Codable {
    var mode: NetworkMode
    var bridgedInterface: String?
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
