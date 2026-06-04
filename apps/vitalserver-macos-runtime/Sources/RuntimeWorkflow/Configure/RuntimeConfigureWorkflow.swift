import Contracts
import Foundation

public enum RuntimeConfigureWorkflowError: Error, Equatable {
    case invalidArgument(String)
}

public struct RuntimeConfigureWorkflowInput<NetworkMode: Equatable>: Equatable {
    public let changes: [RuntimeConfigureWorkflowChange<NetworkMode>]
    public let restart: Bool

    public init(
        changes: [RuntimeConfigureWorkflowChange<NetworkMode>] = [],
        restart: Bool = false
    ) {
        self.changes = changes
        self.restart = restart
    }
}

public enum RuntimeConfigureWorkflowChange<NetworkMode: Equatable>: Equatable {
    case cpu(Int)
    case memoryGiB(UInt64)
    case diskGiB(Int)
    case network(NetworkMode)
    case bridgedInterface(String)
    case proxyPort(Int)
    case vitalFilesDirectory(URL)
    case vitalServerURL(String)
    case remoteConsoleURL(String)
    case publicHost(String)
    case publicPort(Int)
    case adminPassword(String)
    case adminPasswordFile(URL)
    case startOnBoot(Bool)
    case autoRecovery(Bool)
    case preventSystemSleep(Bool)
    case redisBackupRetention(Int)
}

public struct RuntimeConfigureWorkflowResult: Equatable, Sendable {
    public let restart: Bool

    public init(restart: Bool) {
        self.restart = restart
    }
}

public protocol RuntimeConfigureMutableVMRuntimeConfiguration {
    associatedtype ConfigureNetworkMode: Equatable

    var configureCPUCount: Int { get set }
    var configureMemoryMiB: UInt64 { get set }
    var configureNetworkMode: ConfigureNetworkMode { get set }
    var configureBridgedInterface: String? { get set }
    var configureAutoRecoveryEnabled: Bool? { get set }
    var configurePreventSystemSleep: Bool? { get set }

    mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration)
}

public struct RuntimeConfigureWorkflowContext<NetworkMode: Equatable> {
    public let vmConfigURL: URL
    public let guestRuntimeConfigURL: URL
    public let guestRuntimeSettingsURL: URL
    public let minimumCPUCount: Int
    public let maximumAllowedCPUCount: Int
    public let minimumMemoryGiB: Int
    public let maximumAllowedMemoryGiB: Int
    public let memoryStepGiB: Int
    public let minimumDiskGiB: Int
    public let maximumDiskGiB: Int
    public let diskStepGiB: Int
    public let maximumRedisBackupRetentionCount: Int
    public let sharedNetworkMode: NetworkMode
    public let bridgedNetworkMode: NetworkMode
    public let vitalFilesDirectoryTag: String
    public let vitalFilesDirectoryGuestMountPath: String

    public init(
        vmConfigURL: URL,
        guestRuntimeConfigURL: URL,
        guestRuntimeSettingsURL: URL,
        minimumCPUCount: Int,
        maximumAllowedCPUCount: Int,
        minimumMemoryGiB: Int,
        maximumAllowedMemoryGiB: Int,
        memoryStepGiB: Int,
        minimumDiskGiB: Int,
        maximumDiskGiB: Int,
        diskStepGiB: Int,
        maximumRedisBackupRetentionCount: Int,
        sharedNetworkMode: NetworkMode,
        bridgedNetworkMode: NetworkMode,
        vitalFilesDirectoryTag: String,
        vitalFilesDirectoryGuestMountPath: String
    ) {
        self.vmConfigURL = vmConfigURL
        self.guestRuntimeConfigURL = guestRuntimeConfigURL
        self.guestRuntimeSettingsURL = guestRuntimeSettingsURL
        self.minimumCPUCount = minimumCPUCount
        self.maximumAllowedCPUCount = maximumAllowedCPUCount
        self.minimumMemoryGiB = minimumMemoryGiB
        self.maximumAllowedMemoryGiB = maximumAllowedMemoryGiB
        self.memoryStepGiB = memoryStepGiB
        self.minimumDiskGiB = minimumDiskGiB
        self.maximumDiskGiB = maximumDiskGiB
        self.diskStepGiB = diskStepGiB
        self.maximumRedisBackupRetentionCount = maximumRedisBackupRetentionCount
        self.sharedNetworkMode = sharedNetworkMode
        self.bridgedNetworkMode = bridgedNetworkMode
        self.vitalFilesDirectoryTag = vitalFilesDirectoryTag
        self.vitalFilesDirectoryGuestMountPath = vitalFilesDirectoryGuestMountPath
    }
}

public struct RuntimeConfigureWorkflowOperations<VMConfig: RuntimeConfigureMutableVMRuntimeConfiguration> {
    public let loadVMConfig: (URL) throws -> VMConfig
    public let loadGuestRuntimeConfig: (URL) throws -> GuestRuntimeConfigDocument
    public let encodeVMConfig: (VMConfig) throws -> Data
    public let encodeGuestRuntimeConfig: (GuestRuntimeConfigDocument) throws -> Data
    public let encodeGuestRuntimeSettings: (GuestRuntimeSettingsDocument) throws -> Data
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let resizeVMDiskIfNeeded: (Int) throws -> Void
    public let setInstalledProxyPort: (Int) throws -> Void
    public let readSecretFile: (URL) throws -> String
    public let restrictSecretFile: (URL) throws -> Void
    public let setStartOnBoot: (Bool) throws -> Void
    public let setSystemSleepPrevention: (Bool) throws -> Void
    public let restartRuntimeServices: () throws -> Void
    public let ensureRuntimeDefaults: (inout VMConfig) -> Void
    public let log: (String) -> Void

    public init(
        loadVMConfig: @escaping (URL) throws -> VMConfig,
        loadGuestRuntimeConfig: @escaping (URL) throws -> GuestRuntimeConfigDocument,
        encodeVMConfig: @escaping (VMConfig) throws -> Data,
        encodeGuestRuntimeConfig: @escaping (GuestRuntimeConfigDocument) throws -> Data,
        encodeGuestRuntimeSettings: @escaping (GuestRuntimeSettingsDocument) throws -> Data,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        resizeVMDiskIfNeeded: @escaping (Int) throws -> Void,
        setInstalledProxyPort: @escaping (Int) throws -> Void,
        readSecretFile: @escaping (URL) throws -> String,
        restrictSecretFile: @escaping (URL) throws -> Void,
        setStartOnBoot: @escaping (Bool) throws -> Void,
        setSystemSleepPrevention: @escaping (Bool) throws -> Void,
        restartRuntimeServices: @escaping () throws -> Void,
        ensureRuntimeDefaults: @escaping (inout VMConfig) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.loadVMConfig = loadVMConfig
        self.loadGuestRuntimeConfig = loadGuestRuntimeConfig
        self.encodeVMConfig = encodeVMConfig
        self.encodeGuestRuntimeConfig = encodeGuestRuntimeConfig
        self.encodeGuestRuntimeSettings = encodeGuestRuntimeSettings
        self.writeData = writeData
        self.createDirectory = createDirectory
        self.resizeVMDiskIfNeeded = resizeVMDiskIfNeeded
        self.setInstalledProxyPort = setInstalledProxyPort
        self.readSecretFile = readSecretFile
        self.restrictSecretFile = restrictSecretFile
        self.setStartOnBoot = setStartOnBoot
        self.setSystemSleepPrevention = setSystemSleepPrevention
        self.restartRuntimeServices = restartRuntimeServices
        self.ensureRuntimeDefaults = ensureRuntimeDefaults
        self.log = log
    }
}

public struct RuntimeConfigureWorkflow<VMConfig: RuntimeConfigureMutableVMRuntimeConfiguration> {
    public let context: RuntimeConfigureWorkflowContext<VMConfig.ConfigureNetworkMode>
    public let operations: RuntimeConfigureWorkflowOperations<VMConfig>

    public init(
        context: RuntimeConfigureWorkflowContext<VMConfig.ConfigureNetworkMode>,
        operations: RuntimeConfigureWorkflowOperations<VMConfig>
    ) {
        self.context = context
        self.operations = operations
    }

    public func configure(
        _ input: RuntimeConfigureWorkflowInput<VMConfig.ConfigureNetworkMode>
    ) throws -> RuntimeConfigureWorkflowResult {
        var vmConfig = try operations.loadVMConfig(context.vmConfigURL)
        var guestConfig = try operations.loadGuestRuntimeConfig(context.guestRuntimeConfigURL)

        for change in input.changes {
            try apply(change, vmConfig: &vmConfig, guestConfig: &guestConfig)
        }

        try validate(vmConfig)
        operations.ensureRuntimeDefaults(&vmConfig)
        try operations.writeData(try operations.encodeVMConfig(vmConfig), context.vmConfigURL, .atomic)
        try operations.writeData(
            try operations.encodeGuestRuntimeConfig(guestConfig),
            context.guestRuntimeConfigURL,
            .atomic
        )
        try operations.writeData(
            try operations.encodeGuestRuntimeSettings(GuestRuntimeSettingsDocument(runtimeConfig: guestConfig)),
            context.guestRuntimeSettingsURL,
            .atomic
        )
        try operations.restrictSecretFile(context.guestRuntimeConfigURL)
        operations.log("runtime configuration updated restart=\(input.restart)")

        if input.restart {
            try operations.restartRuntimeServices()
        }
        return RuntimeConfigureWorkflowResult(restart: input.restart)
    }

    private func apply(
        _ change: RuntimeConfigureWorkflowChange<VMConfig.ConfigureNetworkMode>,
        vmConfig: inout VMConfig,
        guestConfig: inout GuestRuntimeConfigDocument
    ) throws {
        switch change {
        case .cpu(let cpu):
            guard cpu >= context.minimumCPUCount,
                  cpu <= context.maximumAllowedCPUCount else {
                throw invalid("--cpu must be between \(context.minimumCPUCount) and \(context.maximumAllowedCPUCount)")
            }
            vmConfig.configureCPUCount = cpu
        case .memoryGiB(let memoryGiB):
            guard memoryGiB <= UInt64(Int.max),
                  stride(
                    from: context.minimumMemoryGiB,
                    through: context.maximumAllowedMemoryGiB,
                    by: context.memoryStepGiB
                  ).contains(Int(memoryGiB)) else {
                throw invalid(
                    "--memory-gib must be between \(context.minimumMemoryGiB) and "
                        + "\(context.maximumAllowedMemoryGiB) in \(context.memoryStepGiB) GiB steps"
                )
            }
            vmConfig.configureMemoryMiB = memoryGiB * 1024
        case .diskGiB(let diskGiB):
            guard stride(
                    from: context.minimumDiskGiB,
                    through: context.maximumDiskGiB,
                    by: context.diskStepGiB
                  ).contains(diskGiB) else {
                throw invalid(
                    "--disk-gib must be between \(context.minimumDiskGiB) and "
                        + "\(context.maximumDiskGiB) in \(context.diskStepGiB) GiB steps"
                )
            }
            try operations.resizeVMDiskIfNeeded(diskGiB)
        case .network(let mode):
            vmConfig.configureNetworkMode = mode
            if mode == context.sharedNetworkMode {
                vmConfig.configureBridgedInterface = nil
            }
        case .bridgedInterface(let value):
            guard RuntimeTextValidator.isSingleLine(value), !value.isEmpty else {
                throw invalid("--bridged-interface must not be empty or contain newlines")
            }
            vmConfig.configureBridgedInterface = value
        case .proxyPort(let port):
            guard (1...65_535).contains(port) else {
                throw invalid("--proxy-port must be between 1 and 65535")
            }
            try operations.setInstalledProxyPort(port)
        case .vitalFilesDirectory(let url):
            try operations.createDirectory(url, true)
            vmConfig.setConfigureVitalFilesDirectory(RuntimeSharedDirectoryConfiguration(
                hostPath: url.path,
                tag: context.vitalFilesDirectoryTag,
                guestMountPath: context.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            ))
            guestConfig.vitalFilesDirectory = context.vitalFilesDirectoryGuestMountPath
        case .vitalServerURL(let value):
            guard isValidAdvertisedURL(value) else {
                throw invalid("--vitalserver-url must be empty or an absolute http/https URL")
            }
            guestConfig.vitalServerURL = value
            applyVitalServerURLCompatibilityFields(value, to: &guestConfig)
        case .remoteConsoleURL(let value):
            guard isValidAdvertisedURL(value) else {
                throw invalid("--remote-console-url must be empty or an absolute http/https URL")
            }
            guestConfig.remoteConsoleURL = value
        case .publicHost(let value):
            guard RuntimeTextValidator.isSingleLine(value) else {
                throw invalid("--public-host must not contain newlines")
            }
            guestConfig.publicHost = value
        case .publicPort(let port):
            guard (1...65_535).contains(port) else {
                throw invalid("--public-port must be between 1 and 65535")
            }
            guestConfig.publicPort = port
        case .adminPassword(let value):
            guard !value.isEmpty, RuntimeTextValidator.isSingleLine(value) else {
                throw invalid("--admin-password must not be empty or contain newlines")
            }
            guestConfig.adminPassword = value
        case .adminPasswordFile(let url):
            let password = try operations.readSecretFile(url)
            guard !password.isEmpty, RuntimeTextValidator.isSingleLine(password) else {
                throw invalid("--admin-password-file must contain a non-empty single-line password")
            }
            guestConfig.adminPassword = password
        case .startOnBoot(let enabled):
            try operations.setStartOnBoot(enabled)
        case .autoRecovery(let enabled):
            vmConfig.configureAutoRecoveryEnabled = enabled
        case .preventSystemSleep(let enabled):
            vmConfig.configurePreventSystemSleep = enabled
            try operations.setSystemSleepPrevention(enabled)
        case .redisBackupRetention(let count):
            guard (1...context.maximumRedisBackupRetentionCount).contains(count) else {
                throw invalid(
                    "--redis-backup-retention must be between 1 and \(context.maximumRedisBackupRetentionCount)"
                )
            }
            guestConfig.redisBackupRetentionCount = count
        }
    }

    private func isValidAdvertisedURL(_ value: String) -> Bool {
        if value.isEmpty {
            return true
        }
        guard RuntimeTextValidator.isSingleLine(value),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return false
        }
        return true
    }

    private func applyVitalServerURLCompatibilityFields(
        _ value: String,
        to guestConfig: inout GuestRuntimeConfigDocument
    ) {
        guard !value.isEmpty,
              let components = URLComponents(string: value),
              let host = components.host else {
            return
        }
        guestConfig.publicHost = host
        if let port = components.port {
            guestConfig.publicPort = port
        } else if components.scheme?.lowercased() == "https" {
            guestConfig.publicPort = 443
        }
    }

    private func validate(_ vmConfig: VMConfig) throws {
        if vmConfig.configureNetworkMode == context.bridgedNetworkMode,
           vmConfig.configureBridgedInterface?.isEmpty != false {
            throw invalid("--bridged-interface is required when --network bridged")
        }
    }

    private func invalid(_ message: String) -> RuntimeConfigureWorkflowError {
        .invalidArgument(message)
    }
}
