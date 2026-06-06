import Contracts
import Domain
import Foundation
import Errors

public protocol ConfigureRuntimeMutableVMRuntimeConfiguration {
    associatedtype ConfigureNetworkMode: Equatable

    var configureCPUCount: Int { get set }
    var configureMemoryMiB: UInt64 { get set }
    var configureNetworkMode: ConfigureNetworkMode { get set }
    var configureBridgedInterface: String? { get set }
    var configureAutoRecoveryEnabled: Bool? { get set }
    var configurePreventSystemSleep: Bool? { get set }

    mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration)
}

public struct ConfigureRuntimeContext<NetworkMode: Equatable> {
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
    public let defaultPublicPort: Int
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
        defaultPublicPort: Int,
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
        self.defaultPublicPort = defaultPublicPort
        self.sharedNetworkMode = sharedNetworkMode
        self.bridgedNetworkMode = bridgedNetworkMode
        self.vitalFilesDirectoryTag = vitalFilesDirectoryTag
        self.vitalFilesDirectoryGuestMountPath = vitalFilesDirectoryGuestMountPath
    }
}

public struct ConfigureRuntimeRequest<NetworkMode: Equatable>: Equatable {
    public let changes: [ConfigureRuntimeChange<NetworkMode>]
    public let restart: Bool

    public init(
        changes: [ConfigureRuntimeChange<NetworkMode>] = [],
        restart: Bool = false
    ) {
        self.changes = changes
        self.restart = restart
    }
}

public enum ConfigureRuntimeChange<NetworkMode: Equatable>: Equatable {
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

public struct ConfigureRuntimeSecretFileInput: Equatable, Sendable {
    public let path: String
    public let contents: String

    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }
}

public struct ConfigureRuntimeResult: Equatable, Sendable {
    public let restart: Bool

    public init(restart: Bool) {
        self.restart = restart
    }
}

public enum ConfigureRuntimeEffect: Equatable, Sendable {
    case createDirectory(URL, withIntermediateDirectories: Bool)
    case resizeVMDiskIfNeeded(Int)
    case setInstalledProxyPort(Int)
    case restrictSecretFile(URL)
    case setStartOnBoot(Bool)
    case setSystemSleepPrevention(Bool)
    case restartRuntimeServices
}

public struct ConfigureRuntimePlan<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public let vmConfig: VMConfig
    public let guestRuntimeConfig: GuestRuntimeConfigDocument
    public let guestRuntimeSettings: GuestRuntimeSettingsDocument
    public let effects: [ConfigureRuntimeEffect]
    public let restart: Bool
    public let logMessage: String

    public init(
        vmConfig: VMConfig,
        guestRuntimeConfig: GuestRuntimeConfigDocument,
        guestRuntimeSettings: GuestRuntimeSettingsDocument,
        effects: [ConfigureRuntimeEffect],
        restart: Bool,
        logMessage: String
    ) {
        self.vmConfig = vmConfig
        self.guestRuntimeConfig = guestRuntimeConfig
        self.guestRuntimeSettings = guestRuntimeSettings
        self.effects = effects
        self.restart = restart
        self.logMessage = logMessage
    }
}

public struct ConfigureRuntimeUseCase<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public init() {}

    public func resolvedAdminPasswordChange(
        from input: ConfigureRuntimeSecretFileInput
    ) throws -> ConfigureRuntimeChange<VMConfig.ConfigureNetworkMode> {
        guard !input.contents.isEmpty, RuntimeTextValidator.isSingleLine(input.contents) else {
            throw invalid("--admin-password-file must contain a non-empty single-line password path=\(input.path)")
        }
        return .adminPassword(input.contents)
    }

    public func plan(
        _ request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>,
        currentVMConfig: VMConfig,
        currentGuestRuntimeConfig: GuestRuntimeConfigDocument
    ) throws -> ConfigureRuntimePlan<VMConfig> {
        var vmConfig = currentVMConfig
        var guestConfig = currentGuestRuntimeConfig
        var effects: [ConfigureRuntimeEffect] = []

        for change in request.changes {
            try apply(
                change,
                context: context,
                vmConfig: &vmConfig,
                guestConfig: &guestConfig,
                effects: &effects
            )
        }

        try validate(vmConfig, context: context)
        effects.append(.restrictSecretFile(context.guestRuntimeConfigURL))
        if request.restart {
            effects.append(.restartRuntimeServices)
        }

        return ConfigureRuntimePlan(
            vmConfig: vmConfig,
            guestRuntimeConfig: guestConfig,
            guestRuntimeSettings: GuestRuntimeSettingsDocument(runtimeConfig: guestConfig),
            effects: effects,
            restart: request.restart,
            logMessage: "runtime configuration updated restart=\(request.restart)"
        )
    }

    private func apply(
        _ change: ConfigureRuntimeChange<VMConfig.ConfigureNetworkMode>,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>,
        vmConfig: inout VMConfig,
        guestConfig: inout GuestRuntimeConfigDocument,
        effects: inout [ConfigureRuntimeEffect]
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
            effects.append(.resizeVMDiskIfNeeded(diskGiB))
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
            effects.append(.setInstalledProxyPort(port))
        case .vitalFilesDirectory(let url):
            effects.append(.createDirectory(url, withIntermediateDirectories: true))
            vmConfig.setConfigureVitalFilesDirectory(RuntimeSharedDirectoryConfiguration(
                hostPath: url.path,
                tag: context.vitalFilesDirectoryTag,
                guestMountPath: context.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            ))
            guestConfig.vitalFilesDirectory = context.vitalFilesDirectoryGuestMountPath
        case .vitalServerURL(let value):
            guard RuntimeAdvertisedURLPolicy.isValidAdvertisedURL(value) else {
                throw invalid("--vitalserver-url must be an absolute http/https URL")
            }
            guestConfig.vitalServerURL = value
            applyVitalServerURLCompatibilityFields(value, to: &guestConfig, context: context)
        case .remoteConsoleURL(let value):
            guard RuntimeAdvertisedURLPolicy.isValidAdvertisedURL(value) else {
                throw invalid("--remote-console-url must be an absolute http/https URL")
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
            throw invalid("--admin-password-file must be resolved before planning path=\(url.path)")
        case .startOnBoot(let enabled):
            effects.append(.setStartOnBoot(enabled))
        case .autoRecovery(let enabled):
            vmConfig.configureAutoRecoveryEnabled = enabled
        case .preventSystemSleep(let enabled):
            vmConfig.configurePreventSystemSleep = enabled
            effects.append(.setSystemSleepPrevention(enabled))
        case .redisBackupRetention(let count):
            guard (1...context.maximumRedisBackupRetentionCount).contains(count) else {
                throw invalid(
                    "--redis-backup-retention must be between 1 and \(context.maximumRedisBackupRetentionCount)"
                )
            }
            guestConfig.redisBackupRetentionCount = count
        }
    }

    private func applyVitalServerURLCompatibilityFields(
        _ value: String,
        to guestConfig: inout GuestRuntimeConfigDocument,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>
    ) {
        guard let endpoint = RuntimeAdvertisedURLPolicy.compatibilityEndpoint(
            forAdvertisedURL: value,
            defaultPublicPort: context.defaultPublicPort
        ) else {
            return
        }
        guestConfig.publicHost = endpoint.publicHost
        guestConfig.publicPort = endpoint.publicPort
    }

    private func validate(
        _ vmConfig: VMConfig,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>
    ) throws {
        if vmConfig.configureNetworkMode == context.bridgedNetworkMode,
           vmConfig.configureBridgedInterface?.isEmpty != false {
            throw invalid("--bridged-interface is required when --network bridged")
        }
    }

    private func invalid(_ message: String) -> ConfigureRuntimeError {
        .invalidArgument(message)
    }
}
