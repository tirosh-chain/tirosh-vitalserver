import Contracts
import Foundation

public protocol RuntimeInstallMutableVMRuntimeConfiguration {
    associatedtype InstallNetworkMode: Equatable

    var installCPUCount: Int { get set }
    var installMemoryMiB: UInt64 { get set }
    var installNetworkMode: InstallNetworkMode { get set }
    var installBridgedInterface: String? { get set }
    var installPreventSystemSleep: Bool? { get set }
    var installSSHAuthorizedKeys: [String]? { get set }

    mutating func setInstallSharedDirectory(_ directory: RuntimeSharedDirectoryConfiguration)
    mutating func setInstallVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration)
}

public struct RuntimeInstallVMRuntimeConfigurationInput<NetworkMode: Equatable>: Equatable {
    public let cpuCount: Int
    public let memoryGiB: Int
    public let networkMode: NetworkMode
    public let sharedNetworkMode: NetworkMode
    public let dataDirectoryPath: String
    public let sharedDirectoryTag: String
    public let sharedDirectoryGuestMountPath: String
    public let vitalFilesDirectoryPath: String
    public let vitalFilesDirectoryTag: String
    public let vitalFilesDirectoryGuestMountPath: String
    public let preventSystemSleep: Bool
    public let sshAuthorizedKeys: [String]

    public init(
        cpuCount: Int,
        memoryGiB: Int,
        networkMode: NetworkMode,
        sharedNetworkMode: NetworkMode,
        dataDirectoryPath: String,
        sharedDirectoryTag: String,
        sharedDirectoryGuestMountPath: String,
        vitalFilesDirectoryPath: String,
        vitalFilesDirectoryTag: String,
        vitalFilesDirectoryGuestMountPath: String,
        preventSystemSleep: Bool,
        sshAuthorizedKeys: [String] = []
    ) {
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.networkMode = networkMode
        self.sharedNetworkMode = sharedNetworkMode
        self.dataDirectoryPath = dataDirectoryPath
        self.sharedDirectoryTag = sharedDirectoryTag
        self.sharedDirectoryGuestMountPath = sharedDirectoryGuestMountPath
        self.vitalFilesDirectoryPath = vitalFilesDirectoryPath
        self.vitalFilesDirectoryTag = vitalFilesDirectoryTag
        self.vitalFilesDirectoryGuestMountPath = vitalFilesDirectoryGuestMountPath
        self.preventSystemSleep = preventSystemSleep
        self.sshAuthorizedKeys = sshAuthorizedKeys
    }
}

public struct RuntimeInstallVMRuntimeConfigurationContext {
    public let configURL: URL
    public let requiredDirectories: [URL]

    public init(
        configURL: URL,
        requiredDirectories: [URL]
    ) {
        self.configURL = configURL
        self.requiredDirectories = requiredDirectories
    }
}

public struct RuntimeInstallVMRuntimeConfigurationOperations<Config> {
    public let createDirectory: (URL, Bool) throws -> Void
    public let fileExists: (URL) -> Bool
    public let loadConfig: (URL) throws -> Config
    public let defaultConfig: () -> Config
    public let ensureRuntimeDefaults: (inout Config) -> Void
    public let encodeConfig: (Config) throws -> Data
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void

    public init(
        createDirectory: @escaping (URL, Bool) throws -> Void,
        fileExists: @escaping (URL) -> Bool,
        loadConfig: @escaping (URL) throws -> Config,
        defaultConfig: @escaping () -> Config,
        ensureRuntimeDefaults: @escaping (inout Config) -> Void,
        encodeConfig: @escaping (Config) throws -> Data,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void
    ) {
        self.createDirectory = createDirectory
        self.fileExists = fileExists
        self.loadConfig = loadConfig
        self.defaultConfig = defaultConfig
        self.ensureRuntimeDefaults = ensureRuntimeDefaults
        self.encodeConfig = encodeConfig
        self.writeData = writeData
    }
}

public struct RuntimeInstallVMRuntimeConfigurator<Config: RuntimeInstallMutableVMRuntimeConfiguration> {
    public let context: RuntimeInstallVMRuntimeConfigurationContext
    public let operations: RuntimeInstallVMRuntimeConfigurationOperations<Config>

    public init(
        context: RuntimeInstallVMRuntimeConfigurationContext,
        operations: RuntimeInstallVMRuntimeConfigurationOperations<Config>
    ) {
        self.context = context
        self.operations = operations
    }

    public func configure(
        input: RuntimeInstallVMRuntimeConfigurationInput<Config.InstallNetworkMode>
    ) throws {
        for directory in context.requiredDirectories {
            try operations.createDirectory(directory, true)
        }

        var config = try operations.fileExists(context.configURL)
            ? operations.loadConfig(context.configURL)
            : operations.defaultConfig()

        config.installCPUCount = input.cpuCount
        config.installMemoryMiB = UInt64(input.memoryGiB * 1024)
        config.installNetworkMode = input.networkMode
        if input.networkMode == input.sharedNetworkMode {
            config.installBridgedInterface = nil
        }
        config.setInstallSharedDirectory(RuntimeSharedDirectoryConfiguration(
            hostPath: input.dataDirectoryPath,
            tag: input.sharedDirectoryTag,
            guestMountPath: input.sharedDirectoryGuestMountPath,
            readOnly: false
        ))
        config.setInstallVitalFilesDirectory(RuntimeSharedDirectoryConfiguration(
            hostPath: input.vitalFilesDirectoryPath,
            tag: input.vitalFilesDirectoryTag,
            guestMountPath: input.vitalFilesDirectoryGuestMountPath,
            readOnly: false
        ))
        config.installPreventSystemSleep = input.preventSystemSleep
        config.installSSHAuthorizedKeys = input.sshAuthorizedKeys
        operations.ensureRuntimeDefaults(&config)

        let encoded = try operations.encodeConfig(config)
        try operations.createDirectory(context.configURL.deletingLastPathComponent(), true)
        try operations.writeData(encoded, context.configURL, [])
    }
}
