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
    var configureVitalFilesDirectoryHostPath: String? { get }

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
    public let maximumBackupRetentionCount: Int
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
        maximumBackupRetentionCount: Int,
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
        self.maximumBackupRetentionCount = maximumBackupRetentionCount
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
    case recorderIngressSendDataMode(RuntimeRecorderIngressSendDataMode)
    case recorderIngressSendDataReplayBatchSize(Int)
    case recorderIngressSendDataReplayMaxMiBPerSecond(Int)
    case recorderIngress(RuntimeRecorderIngressSettings)
    case containerMemoryLimitsEnabled(Bool)
    case vitalServerContainerMemoryLimitMiB(Int)
    case recorderIngressContainerMemoryLimitMiB(Int)
    case redisContainerMemoryLimitMiB(Int)
    case adminPassword(String)
    case adminPasswordFile(URL)
    case startOnBoot(Bool)
    case autoRecovery(Bool)
    case preventSystemSleep(Bool)
    case automaticBackup(Bool)
    case backupScheduleTimes([String])
    case backupRetention(Int)
    case logArchiveRetentionDays(Int)
    case logArchiveMaximumGiB(Int)
    case redisRelay(ConfigureRuntimeRedisRelaySettings)
}

public enum ConfigureRuntimeRedisRelayScope: String, Equatable, Sendable {
    case waveformTrendOnly = "waveform_trend_only"
    case vitalReconstruction = "vital_reconstruction"
}

public struct ConfigureRuntimeRedisRelayTarget: Equatable, Sendable {
    public static let defaultURL = "redis://redis.example:6379/0"

    public var url: String
    public var username: String
    public var password: String
    public var clearPassword: Bool
    public var passwordConfigured: Bool
    public var tls: Bool

    public init(
        url: String = ConfigureRuntimeRedisRelayTarget.defaultURL,
        username: String = "",
        password: String = "",
        clearPassword: Bool = false,
        passwordConfigured: Bool = false,
        tls: Bool = false
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.clearPassword = clearPassword
        self.passwordConfigured = passwordConfigured
        self.tls = tls
    }
}

public struct ConfigureRuntimeRedisRelaySettings: Equatable, Sendable {
    public var enabled: Bool
    public var target: ConfigureRuntimeRedisRelayTarget
    public var scope: ConfigureRuntimeRedisRelayScope
    public var includeRecorderNetworkContext: Bool
    public var intervalSeconds: Double
    public var scanCount: Int

    public init(
        enabled: Bool = false,
        target: ConfigureRuntimeRedisRelayTarget = ConfigureRuntimeRedisRelayTarget(),
        scope: ConfigureRuntimeRedisRelayScope = .vitalReconstruction,
        includeRecorderNetworkContext: Bool = false,
        intervalSeconds: Double = 1.0,
        scanCount: Int = 1000
    ) {
        self.enabled = enabled
        self.target = target
        self.scope = scope
        self.includeRecorderNetworkContext = includeRecorderNetworkContext
        self.intervalSeconds = intervalSeconds
        self.scanCount = scanCount
    }
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
    public let restartRequirement: ConfigureRuntimeRestartRequirement

    public init(
        restart: Bool,
        restartRequirement: ConfigureRuntimeRestartRequirement = .none
    ) {
        self.restart = restart
        self.restartRequirement = restartRequirement
    }
}

public enum ConfigureRuntimeRestartRequirement: String, Equatable, Sendable {
    case none
    case containerServices
    case vmRuntime

    public var requiresRestart: Bool {
        self != .none
    }
}

public enum ConfigureRuntimeEffect: Equatable, Sendable {
    case createDirectory(URL, withIntermediateDirectories: Bool)
    case resizeVMDiskIfNeeded(Int)
    case setInstalledProxyPort(Int)
    case restrictSecretFile(URL)
    case setStartOnBoot(Bool)
    case setSystemSleepPrevention(Bool)
    case setAutomaticBackupSchedule(enabled: Bool, scheduleTimes: [String])
    case setLogArchiveRetentionDays(Int)
    case setLogArchiveMaximumGiB(Int)
    case writeRedisRelayConfiguration(ConfigureRuntimeRedisRelaySettings)
    case reconcileGuestComposeServices
    case restartRuntimeServices
}

public struct ConfigureRuntimeEffectExecutionPlan: Equatable, Sendable {
    public let preWriteEffects: [ConfigureRuntimeEffect]
    public let postWriteEffects: [ConfigureRuntimeEffect]

    public init(
        preWriteEffects: [ConfigureRuntimeEffect],
        postWriteEffects: [ConfigureRuntimeEffect]
    ) {
        self.preWriteEffects = preWriteEffects
        self.postWriteEffects = postWriteEffects
    }
}

public struct ConfigureRuntimePlan<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public let vmConfig: VMConfig
    public let guestRuntimeConfig: GuestRuntimeConfigDocument
    public let guestRuntimeSettings: GuestRuntimeSettingsDocument
    public let effects: [ConfigureRuntimeEffect]
    public let restart: Bool
    public let restartRequirement: ConfigureRuntimeRestartRequirement
    public let logMessage: String

    public init(
        vmConfig: VMConfig,
        guestRuntimeConfig: GuestRuntimeConfigDocument,
        guestRuntimeSettings: GuestRuntimeSettingsDocument,
        effects: [ConfigureRuntimeEffect],
        restart: Bool,
        restartRequirement: ConfigureRuntimeRestartRequirement,
        logMessage: String
    ) {
        self.vmConfig = vmConfig
        self.guestRuntimeConfig = guestRuntimeConfig
        self.guestRuntimeSettings = guestRuntimeSettings
        self.effects = effects
        self.restart = restart
        self.restartRequirement = restartRequirement
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

    public func effectExecutionPlan(
        _ effects: [ConfigureRuntimeEffect]
    ) -> ConfigureRuntimeEffectExecutionPlan {
        ConfigureRuntimeEffectExecutionPlan(
            preWriteEffects: effects.filter { effect in
                switch effect {
                case .createDirectory,
                     .resizeVMDiskIfNeeded,
                     .setInstalledProxyPort,
                     .setStartOnBoot,
                     .setSystemSleepPrevention:
                    return true
                case .restrictSecretFile,
                     .setAutomaticBackupSchedule,
                     .setLogArchiveRetentionDays,
                     .setLogArchiveMaximumGiB,
                     .writeRedisRelayConfiguration,
                     .reconcileGuestComposeServices,
                     .restartRuntimeServices:
                    return false
                }
            },
            postWriteEffects: effects.filter { effect in
                switch effect {
                case .restrictSecretFile,
                     .setAutomaticBackupSchedule,
                     .setLogArchiveRetentionDays,
                     .setLogArchiveMaximumGiB,
                     .writeRedisRelayConfiguration,
                     .reconcileGuestComposeServices,
                     .restartRuntimeServices:
                    return true
                case .createDirectory,
                     .resizeVMDiskIfNeeded,
                     .setInstalledProxyPort,
                     .setStartOnBoot,
                     .setSystemSleepPrevention:
                    return false
                }
            }
        )
    }

    public func plan(
        _ request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>,
        currentVMConfig: VMConfig,
        currentGuestRuntimeConfig: GuestRuntimeConfigDocument,
        currentGuestRuntimeSettings: GuestRuntimeSettingsDocument,
        currentVMDiskSizeGiB: Int
    ) throws -> ConfigureRuntimePlan<VMConfig> {
        var vmConfig = currentVMConfig
        var guestConfig = currentGuestRuntimeConfig
        var guestRuntimeSettings = currentGuestRuntimeSettings
        var effects: [ConfigureRuntimeEffect] = []

        for change in request.changes {
            try apply(
                change,
                context: context,
                vmConfig: &vmConfig,
                guestConfig: &guestConfig,
                guestRuntimeSettings: &guestRuntimeSettings,
                effects: &effects
            )
        }

        try validate(vmConfig, context: context)
        let requestedDiskGiB = requestedDiskGiB(in: request)
        if let requestedDiskGiB, requestedDiskGiB < currentVMDiskSizeGiB {
            throw invalid("--disk-gib can only increase the VM disk; current disk is \(currentVMDiskSizeGiB) GiB")
        }
        if request.changes.contains(where: \.changesAutomaticBackupSchedule) {
            effects.append(.setAutomaticBackupSchedule(
                enabled: guestRuntimeSettings.automaticBackupEnabled,
                scheduleTimes: guestRuntimeSettings.backupScheduleTimes
            ))
        }
        if let redisRelay = redisRelaySettings(in: request) {
            effects.append(.writeRedisRelayConfiguration(redisRelay))
        }
        effects.append(.restrictSecretFile(context.guestRuntimeConfigURL))
        let restartRequirement = restartRequirement(
            current: currentVMConfig,
            planned: vmConfig,
            currentVMDiskSizeGiB: currentVMDiskSizeGiB,
            requestedDiskGiB: requestedDiskGiB,
            changes: request.changes
        )
        let restart = request.restart && restartRequirement.requiresRestart
        if restart, let activationEffect = activationEffect(for: restartRequirement) {
            effects.append(activationEffect)
        }

        return ConfigureRuntimePlan(
            vmConfig: vmConfig,
            guestRuntimeConfig: guestConfig,
            guestRuntimeSettings: guestRuntimeSettings,
            effects: effects,
            restart: restart,
            restartRequirement: restartRequirement,
            logMessage: "runtime configuration updated restart=\(restart) restartRequirement=\(restartRequirement.rawValue)"
        )
    }

    public func restartRequirement(
        current: VMConfig,
        planned: VMConfig,
        currentVMDiskSizeGiB: Int,
        requestedDiskGiB: Int?,
        changes: [ConfigureRuntimeChange<VMConfig.ConfigureNetworkMode>] = []
    ) -> ConfigureRuntimeRestartRequirement {
        if let requestedDiskGiB, requestedDiskGiB > currentVMDiskSizeGiB {
            return .vmRuntime
        }
        if current.configureCPUCount != planned.configureCPUCount {
            return .vmRuntime
        }
        if current.configureMemoryMiB != planned.configureMemoryMiB {
            return .vmRuntime
        }
        if current.configureNetworkMode != planned.configureNetworkMode {
            return .vmRuntime
        }
        if current.configureBridgedInterface != planned.configureBridgedInterface {
            return .vmRuntime
        }
        if current.configureVitalFilesDirectoryHostPath != planned.configureVitalFilesDirectoryHostPath {
            return .vmRuntime
        }
        if changes.contains(where: \.changesRedisRelay) {
            return .containerServices
        }
        if changes.contains(where: \.changesRecorderIngressSendDataConfig) {
            return .containerServices
        }
        return .none
    }

    private func activationEffect(
        for requirement: ConfigureRuntimeRestartRequirement
    ) -> ConfigureRuntimeEffect? {
        switch requirement {
        case .none:
            return nil
        case .containerServices:
            return .reconcileGuestComposeServices
        case .vmRuntime:
            return .restartRuntimeServices
        }
    }

    private func requestedDiskGiB(
        in request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>
    ) -> Int? {
        request.changes.reduce(nil) { requestedDiskGiB, change in
            switch change {
            case .diskGiB(let diskGiB):
                return diskGiB
            default:
                return requestedDiskGiB
            }
        }
    }

    private func redisRelaySettings(
        in request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>
    ) -> ConfigureRuntimeRedisRelaySettings? {
        request.changes.reduce(nil) { settings, change in
            switch change {
            case .redisRelay(let redisRelay):
                return redisRelay
            default:
                return settings
            }
        }
    }

    private func apply(
        _ change: ConfigureRuntimeChange<VMConfig.ConfigureNetworkMode>,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>,
        vmConfig: inout VMConfig,
        guestConfig: inout GuestRuntimeConfigDocument,
        guestRuntimeSettings: inout GuestRuntimeSettingsDocument,
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
            guestRuntimeSettings.vitalServerURL = value
            applyVitalServerURLCompatibilityFields(value, to: &guestConfig, context: context)
            guestRuntimeSettings.publicHost = guestConfig.publicHost
            guestRuntimeSettings.publicPort = guestConfig.publicPort
        case .remoteConsoleURL(let value):
            guard RuntimeAdvertisedURLPolicy.isValidAdvertisedURL(value) else {
                throw invalid("--remote-console-url must be an absolute http/https URL")
            }
            guestConfig.remoteConsoleURL = value
            guestRuntimeSettings.remoteConsoleURL = value
        case .publicHost(let value):
            guard RuntimeTextValidator.isSingleLine(value) else {
                throw invalid("--public-host must not contain newlines")
            }
            guestConfig.publicHost = value
            guestRuntimeSettings.publicHost = value
        case .publicPort(let port):
            guard (1...65_535).contains(port) else {
                throw invalid("--public-port must be between 1 and 65535")
            }
            guestConfig.publicPort = port
            guestRuntimeSettings.publicPort = port
        case .recorderIngressSendDataMode(let mode):
            guestRuntimeSettings.recorderIngressSendDataMode = mode
        case .recorderIngressSendDataReplayBatchSize(let value):
            guard value > 0 else {
                throw invalid("--recorder-ingress-send-data-replay-batch-size must be greater than 0")
            }
            guestRuntimeSettings.recorderIngressSendDataReplayBatchSize = value
        case .recorderIngressSendDataReplayMaxMiBPerSecond(let value):
            guard value > 0 else {
                throw invalid("--recorder-ingress-send-data-replay-max-mib-per-second must be greater than 0")
            }
            guestRuntimeSettings.recorderIngressSendDataReplayMaxMiBPerSecond = value
        case .recorderIngress(let value):
            try validateRecorderIngressSettings(value)
            guestRuntimeSettings.recorderIngress = value
        case .containerMemoryLimitsEnabled(let enabled):
            guestRuntimeSettings.containerMemoryLimitsEnabled = enabled
        case .vitalServerContainerMemoryLimitMiB(let value):
            guard value > 0 else {
                throw invalid("--vitalserver-container-memory-limit-mib must be greater than 0")
            }
            guestRuntimeSettings.vitalServerContainerMemoryLimitMiB = value
        case .recorderIngressContainerMemoryLimitMiB(let value):
            guard value > 0 else {
                throw invalid("--recorder-ingress-container-memory-limit-mib must be greater than 0")
            }
            guestRuntimeSettings.recorderIngressContainerMemoryLimitMiB = value
        case .redisContainerMemoryLimitMiB(let value):
            guard value > 0 else {
                throw invalid("--redis-container-memory-limit-mib must be greater than 0")
            }
            guestRuntimeSettings.redisContainerMemoryLimitMiB = value
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
        case .automaticBackup(let enabled):
            guestRuntimeSettings.automaticBackupEnabled = enabled
        case .backupScheduleTimes(let scheduleTimes):
            guard RuntimeBackupSchedulePolicy.isValidSchedule(scheduleTimes) else {
                throw invalid("--backup-schedule-times must be unique comma-separated HH:mm values")
            }
            guestRuntimeSettings.backupScheduleTimes = scheduleTimes
        case .backupRetention(let count):
            guard RuntimeBackupSchedulePolicy.isValidRetentionCount(count),
                  count <= context.maximumBackupRetentionCount else {
                throw invalid(
                    "--backup-retention must be between 1 and \(context.maximumBackupRetentionCount)"
                )
            }
            guestRuntimeSettings.backupRetentionCount = count
        case .logArchiveRetentionDays(let days):
            guard (1...30).contains(days) else {
                throw invalid(
                    "--log-archive-retention-days must be between 1 and 30"
                )
            }
            effects.append(.setLogArchiveRetentionDays(days))
        case .logArchiveMaximumGiB(let gib):
            guard (1...20).contains(gib) else {
                throw invalid("--log-archive-maximum-gib must be between 1 and 20")
            }
            effects.append(.setLogArchiveMaximumGiB(gib))
        case .redisRelay(let settings):
            try validate(redisRelay: settings)
        }
    }

    private func validate(redisRelay settings: ConfigureRuntimeRedisRelaySettings) throws {
        guard settings.intervalSeconds >= 0.1 else {
            throw invalid("--redis-relay-settings-file intervalSeconds must be greater than or equal to 0.1")
        }
        guard settings.scanCount >= 1 else {
            throw invalid("--redis-relay-settings-file scanCount must be greater than or equal to 1")
        }
        guard !settings.target.url.contains("\n"),
              !settings.target.url.contains("\r"),
              !settings.target.username.contains("\n"),
              !settings.target.username.contains("\r"),
              !settings.target.password.contains("\n"),
              !settings.target.password.contains("\r") else {
            throw invalid("--redis-relay-settings-file target values must not contain newlines")
        }
        if settings.enabled {
            try validateRedisRelayTargetURL(settings.target.url)
        }
    }

    private func validateRedisRelayTargetURL(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw invalid("--redis-relay-settings-file target url is required when relay is enabled")
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme,
              ["redis", "rediss"].contains(scheme),
              components.host?.isEmpty == false else {
            throw invalid("--redis-relay-settings-file target url must be redis:// or rediss://")
        }
        if let port = components.port, !(1...65_535).contains(port) {
            throw invalid("--redis-relay-settings-file target url port must be between 1 and 65535")
        }
        let path = components.path
        if !path.isEmpty, path != "/" {
            let rawDatabase = String(path.dropFirst())
            guard !rawDatabase.contains("/"), let database = Int(rawDatabase), database >= 0 else {
                throw invalid("--redis-relay-settings-file target url database path must be /<number>")
            }
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

    private func validateRecorderIngressSettings(
        _ settings: RuntimeRecorderIngressSettings
    ) throws {
        let positiveFields: [(String, Int)] = [
            ("sendDataMaxPendingItems", settings.sendDataMaxPendingItems),
            ("sendDataMaxPendingMiB", settings.sendDataMaxPendingMiB),
            ("sendDataMaxPayloadMiB", settings.sendDataMaxPayloadMiB),
            ("sendDataReplayedMaxItems", settings.sendDataReplayedMaxItems),
            ("sendDataRealtimeMaxPendingItems", settings.sendDataRealtimeMaxPendingItems),
            ("sendDataReplayIntervalMs", settings.sendDataReplayIntervalMs),
            ("sendDataReplayMaxAttempts", settings.sendDataReplayMaxAttempts),
            ("sendDataReplayTargetTimeoutMs", settings.sendDataReplayTargetTimeoutMs),
            ("sendDataReplayAdaptiveMinConcurrency", settings.sendDataReplayAdaptiveMinConcurrency),
            ("sendDataReplayAdaptiveMaxConcurrency", settings.sendDataReplayAdaptiveMaxConcurrency),
            ("rawArchiveMaxFileMiB", settings.rawArchiveMaxFileMiB),
            ("rawArchiveMaxFiles", settings.rawArchiveMaxFiles),
            ("rawArchiveAutoExportQuietSeconds", settings.rawArchiveAutoExportQuietSeconds),
            ("rawArchiveAutoExportScanIntervalSeconds", settings.rawArchiveAutoExportScanIntervalSeconds),
            ("rawArchiveAutoExportCursorStableSeconds", settings.rawArchiveAutoExportCursorStableSeconds),
            ("rawArchiveAutoExportRetryDelaySeconds", settings.rawArchiveAutoExportRetryDelaySeconds),
            ("rawArchiveAutoExportMaxAttempts", settings.rawArchiveAutoExportMaxAttempts),
            ("rawArchiveAutoExportRequestTimeoutSeconds", settings.rawArchiveAutoExportRequestTimeoutSeconds),
        ]
        if let invalidField = positiveFields.first(where: { $0.1 <= 0 }) {
            throw invalid("--recorder-ingress-settings-file \(invalidField.0) must be greater than 0")
        }
        guard settings.sendDataReplayAdaptiveMaxConcurrency >= settings.sendDataReplayAdaptiveMinConcurrency else {
            throw invalid("--recorder-ingress-settings-file sendDataReplayAdaptiveMaxConcurrency must be greater than or equal to min concurrency")
        }
    }

    private func invalid(_ message: String) -> ConfigureRuntimeError {
        .invalidArgument(message)
    }
}

private extension ConfigureRuntimeChange {
    var changesAutomaticBackupSchedule: Bool {
        switch self {
        case .automaticBackup, .backupScheduleTimes:
            return true
        default:
            return false
        }
    }

    var changesRedisRelay: Bool {
        switch self {
        case .redisRelay:
            return true
        default:
            return false
        }
    }

    var changesRecorderIngressSendDataConfig: Bool {
        switch self {
        case .recorderIngressSendDataMode,
             .recorderIngressSendDataReplayBatchSize,
             .recorderIngressSendDataReplayMaxMiBPerSecond,
             .recorderIngress,
             .containerMemoryLimitsEnabled,
             .vitalServerContainerMemoryLimitMiB,
             .recorderIngressContainerMemoryLimitMiB,
             .redisContainerMemoryLimitMiB:
            return true
        default:
            return false
        }
    }
}
