import Application
import Contracts
import Foundation
import Workflow
import Errors

public struct VMRuntimeConfig: Codable {
    public var cpuCount: Int
    public var memoryMiB: UInt64
    public var kernelPath: String
    public var initialRamdiskPath: String?
    public var diskPath: String?
    public var cloudInitPath: String?
    public var kernelCommandLine: String
    public var network: NetworkConfig
    public var sharedDirectory: SharedDirectoryConfig?
    public var vitalFilesDirectory: SharedDirectoryConfig?
    public var autoRecoveryEnabled: Bool?
    public var preventSystemSleep: Bool?
    public var sshAuthorizedKeys: [String]?

    public init(
        cpuCount: Int,
        memoryMiB: UInt64,
        kernelPath: String,
        initialRamdiskPath: String?,
        diskPath: String?,
        cloudInitPath: String?,
        kernelCommandLine: String,
        network: NetworkConfig,
        sharedDirectory: SharedDirectoryConfig?,
        vitalFilesDirectory: SharedDirectoryConfig?,
        autoRecoveryEnabled: Bool? = nil,
        preventSystemSleep: Bool? = nil,
        sshAuthorizedKeys: [String]? = nil
    ) {
        self.cpuCount = cpuCount
        self.memoryMiB = memoryMiB
        self.kernelPath = kernelPath
        self.initialRamdiskPath = initialRamdiskPath
        self.diskPath = diskPath
        self.cloudInitPath = cloudInitPath
        self.kernelCommandLine = kernelCommandLine
        self.network = network
        self.sharedDirectory = sharedDirectory
        self.vitalFilesDirectory = vitalFilesDirectory
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
        self.sshAuthorizedKeys = sshAuthorizedKeys
    }

    public static func readDocument(from url: URL, fileStore: RuntimeFileReading) throws -> VMRuntimeConfig {
        guard fileStore.fileExists(url) else {
            throw VMRuntimeConfigReadError.missingConfig(url.path)
        }
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(VMRuntimeConfig.self, from: data)
    }

    public static func validateBootFilePaths(_ config: VMRuntimeConfig, fileStore: RuntimeFileReading) throws {
        for path in [config.kernelPath, config.initialRamdiskPath, config.diskPath].compactMap({ $0 }) {
            guard fileStore.fileExists(URL(fileURLWithPath: path)) else {
                throw VMRuntimeBootFileValidationError.missingFile(path)
            }
        }
    }

    public static func ensureNetworkIdentity(_ config: inout VMRuntimeConfig, localMacPrefix0: UInt8) {
        if config.network.macAddress == nil || config.network.macAddress?.isEmpty == true {
            config.network.macAddress = generateMacAddress(localMacPrefix0: localMacPrefix0)
        }
    }

    private static func generateMacAddress(localMacPrefix0: UInt8) -> String {
        let bytes = [
            localMacPrefix0,
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
        ]
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

public struct NetworkConfig: Codable {
    public var mode: RuntimeNetworkMode
    public var bridgedInterface: String?
    public var macAddress: String?

    public init(mode: RuntimeNetworkMode, bridgedInterface: String?, macAddress: String?) {
        self.mode = mode
        self.bridgedInterface = bridgedInterface
        self.macAddress = macAddress
    }
}

public struct SharedDirectoryConfig: Codable {
    public var hostPath: String
    public var tag: String
    public var guestMountPath: String
    public var readOnly: Bool

    public init(hostPath: String, tag: String, guestMountPath: String, readOnly: Bool) {
        self.hostPath = hostPath
        self.tag = tag
        self.guestMountPath = guestMountPath
        self.readOnly = readOnly
    }
}

extension VMRuntimeConfig: RuntimeInstallMutableVMRuntimeConfiguration {
    public var installCPUCount: Int {
        get { cpuCount }
        set { cpuCount = newValue }
    }

    public var installMemoryMiB: UInt64 {
        get { memoryMiB }
        set { memoryMiB = newValue }
    }

    public var installNetworkMode: RuntimeNetworkMode {
        get { network.mode }
        set { network.mode = newValue }
    }

    public var installBridgedInterface: String? {
        get { network.bridgedInterface }
        set { network.bridgedInterface = newValue }
    }

    public var installPreventSystemSleep: Bool? {
        get { preventSystemSleep }
        set { preventSystemSleep = newValue }
    }

    public var installSSHAuthorizedKeys: [String]? {
        get { sshAuthorizedKeys }
        set { sshAuthorizedKeys = newValue }
    }

    public mutating func setInstallSharedDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        sharedDirectory = SharedDirectoryConfig(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }

    public mutating func setInstallVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = SharedDirectoryConfig(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }
}

extension VMRuntimeConfig: ConfigureRuntimeMutableVMRuntimeConfiguration {
    public var configureCPUCount: Int {
        get { cpuCount }
        set { cpuCount = newValue }
    }

    public var configureMemoryMiB: UInt64 {
        get { memoryMiB }
        set { memoryMiB = newValue }
    }

    public var configureNetworkMode: RuntimeNetworkMode {
        get { network.mode }
        set { network.mode = newValue }
    }

    public var configureBridgedInterface: String? {
        get { network.bridgedInterface }
        set { network.bridgedInterface = newValue }
    }

    public var configureAutoRecoveryEnabled: Bool? {
        get { autoRecoveryEnabled }
        set { autoRecoveryEnabled = newValue }
    }

    public var configurePreventSystemSleep: Bool? {
        get { preventSystemSleep }
        set { preventSystemSleep = newValue }
    }

    public mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = SharedDirectoryConfig(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }
}
