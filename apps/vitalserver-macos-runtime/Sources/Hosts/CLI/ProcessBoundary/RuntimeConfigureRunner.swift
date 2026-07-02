import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
import RuntimeControl
import Errors

public struct RuntimeConfigureActions {
    public var resizeVMDiskIfNeeded: (Int) throws -> Void
    public var setInstalledProxyPort: (Int) throws -> Void
    public var readSecretFile: (URL) throws -> String
    public var restrictSecretFile: (URL) throws -> Void
    public var setStartOnBoot: (Bool) throws -> Void
    public var setSystemSleepPrevention: (Bool) throws -> Void
    public var setAutomaticBackupSchedule: (Bool, [String]) throws -> Void
    public var reconcileGuestStackServices: () throws -> Void
    public var restartRuntimeServices: () throws -> Void

    public init(
        resizeVMDiskIfNeeded: @escaping (Int) throws -> Void,
        setInstalledProxyPort: @escaping (Int) throws -> Void,
        readSecretFile: @escaping (URL) throws -> String,
        restrictSecretFile: @escaping (URL) throws -> Void,
        setStartOnBoot: @escaping (Bool) throws -> Void,
        setSystemSleepPrevention: @escaping (Bool) throws -> Void,
        setAutomaticBackupSchedule: @escaping (Bool, [String]) throws -> Void,
        reconcileGuestStackServices: @escaping () throws -> Void,
        restartRuntimeServices: @escaping () throws -> Void
    ) {
        self.resizeVMDiskIfNeeded = resizeVMDiskIfNeeded
        self.setInstalledProxyPort = setInstalledProxyPort
        self.readSecretFile = readSecretFile
        self.restrictSecretFile = restrictSecretFile
        self.setStartOnBoot = setStartOnBoot
        self.setSystemSleepPrevention = setSystemSleepPrevention
        self.setAutomaticBackupSchedule = setAutomaticBackupSchedule
        self.reconcileGuestStackServices = reconcileGuestStackServices
        self.restartRuntimeServices = restartRuntimeServices
    }
}

public struct RuntimeConfigureResult: Equatable {
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

public struct RuntimeConfigureCompositionContext {
    let installedPaths: InstalledRuntimePaths
    let configURL: URL
    let maximumAllowedCPUCount: Int
    let maximumAllowedMemoryGiB: Int

    public init(
        installedPaths: InstalledRuntimePaths,
        configURL: URL,
        maximumAllowedCPUCount: Int,
        maximumAllowedMemoryGiB: Int
    ) {
        self.installedPaths = installedPaths
        self.configURL = configURL
        self.maximumAllowedCPUCount = maximumAllowedCPUCount
        self.maximumAllowedMemoryGiB = maximumAllowedMemoryGiB
    }
}

public struct RuntimeConfigureCompositionOperations {
    let fileStore: RuntimeFileStore
    let resizeVMDiskIfNeeded: (Int) throws -> Void
    let setInstalledProxyPort: (Int) throws -> Void
    let readSecretFile: (URL) throws -> String
    let restrictSecretFile: (URL) throws -> Void
    let setStartOnBoot: (Bool) throws -> Void
    let setSystemSleepPrevention: (Bool) throws -> Void
    let setAutomaticBackupSchedule: (Bool, [String]) throws -> Void
    let reconcileGuestStackServices: () throws -> Void
    let restartRuntimeServices: () throws -> Void
    let log: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        resizeVMDiskIfNeeded: @escaping (Int) throws -> Void,
        setInstalledProxyPort: @escaping (Int) throws -> Void,
        readSecretFile: @escaping (URL) throws -> String,
        restrictSecretFile: @escaping (URL) throws -> Void,
        setStartOnBoot: @escaping (Bool) throws -> Void,
        setSystemSleepPrevention: @escaping (Bool) throws -> Void,
        setAutomaticBackupSchedule: @escaping (Bool, [String]) throws -> Void,
        reconcileGuestStackServices: @escaping () throws -> Void,
        restartRuntimeServices: @escaping () throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.resizeVMDiskIfNeeded = resizeVMDiskIfNeeded
        self.setInstalledProxyPort = setInstalledProxyPort
        self.readSecretFile = readSecretFile
        self.restrictSecretFile = restrictSecretFile
        self.setStartOnBoot = setStartOnBoot
        self.setSystemSleepPrevention = setSystemSleepPrevention
        self.setAutomaticBackupSchedule = setAutomaticBackupSchedule
        self.reconcileGuestStackServices = reconcileGuestStackServices
        self.restartRuntimeServices = restartRuntimeServices
        self.log = log
    }
}

public enum RuntimeConfigureComposition {
    public static func make(
        context: RuntimeConfigureCompositionContext,
        operations: RuntimeConfigureCompositionOperations
    ) -> RuntimeConfigureRunner {
        RuntimeConfigureRunner(
            installedPaths: context.installedPaths,
            configURL: context.configURL,
            fileStore: operations.fileStore,
            actions: RuntimeConfigureActions(
                resizeVMDiskIfNeeded: operations.resizeVMDiskIfNeeded,
                setInstalledProxyPort: operations.setInstalledProxyPort,
                readSecretFile: operations.readSecretFile,
                restrictSecretFile: operations.restrictSecretFile,
                setStartOnBoot: operations.setStartOnBoot,
                setSystemSleepPrevention: operations.setSystemSleepPrevention,
                setAutomaticBackupSchedule: operations.setAutomaticBackupSchedule,
                reconcileGuestStackServices: operations.reconcileGuestStackServices,
                restartRuntimeServices: operations.restartRuntimeServices
            ),
            maximumAllowedCPUCount: context.maximumAllowedCPUCount,
            maximumAllowedMemoryGiB: context.maximumAllowedMemoryGiB,
            log: operations.log
        )
    }
}

public struct RuntimeConfigureRunner {
    private let installedPaths: InstalledRuntimePaths
    private let configURL: URL
    private let fileStore: RuntimeFileStore
    private let actions: RuntimeConfigureActions
    private let maximumAllowedCPUCount: Int
    private let maximumAllowedMemoryGiB: Int
    private let log: (String) -> Void

    public init(
        installedPaths: InstalledRuntimePaths,
        configURL: URL,
        fileStore: RuntimeFileStore,
        actions: RuntimeConfigureActions,
        maximumAllowedCPUCount: Int,
        maximumAllowedMemoryGiB: Int,
        log: @escaping (String) -> Void
    ) {
        self.installedPaths = installedPaths
        self.configURL = configURL
        self.fileStore = fileStore
        self.actions = actions
        self.maximumAllowedCPUCount = maximumAllowedCPUCount
        self.maximumAllowedMemoryGiB = maximumAllowedMemoryGiB
        self.log = log
    }

    public func configure(_ command: RuntimeConfigureCommand) throws -> RuntimeConfigureResult {
        do {
            let result = try RunConfigureRuntimeUseCase<VMRuntimeConfig>().configure(
                configureRuntimeRequest(from: command),
                context: configureRuntimeContext(),
                operations: configureRuntimeOperations()
            )
            return RuntimeConfigureResult(
                restart: result.restart,
                restartRequirement: result.restartRequirement
            )
        } catch ConfigureRuntimeError.invalidArgument(let message) {
            throw LauncherError.missingArgument(message)
        }
    }

    private func configureRuntimeOperations() -> ConfigureRuntimeOperations<VMRuntimeConfig> {
        ConfigureRuntimeOperations(
            readers: ConfigureRuntimeStateReaders(
                loadVMConfig: { url in
                    try VMRuntimeConfigComposition.load(from: url, fileStore: fileStore)
                },
                loadGuestRuntimeConfig: { url in
                    try loadGuestRuntimeConfig(from: url)
                },
                loadGuestRuntimeSettings: { url in
                    try loadGuestRuntimeSettings(from: url)
                },
                loadVMDiskSizeGiB: {
                    try loadVMDiskSizeGiB()
                }
            ),
            writer: ConfigureRuntimeDocumentWriter(
                encodeVMConfig: { config in
                    try prettyJSONEncoder().encode(config)
                },
                encodeGuestRuntimeConfig: { config in
                    try prettyJSONEncoder().encode(config)
                },
                encodeGuestRuntimeSettings: { settings in
                    try prettyJSONEncoder().encode(settings)
                },
                writeData: { data, url, options in
                    try fileStore.writeData(data, to: url, options: options)
                }
            ),
            effects: ConfigureRuntimeEffects(
                resolveSecretFileChanges: { request in
                    try resolveSecretFileChanges(in: request)
                },
                executeEffects: { effects in
                    try executeConfigureEffects(effects)
                },
                ensureRuntimeDefaults: { config in
                    VMRuntimeConfigComposition.ensureRuntimeDefaults(&config, paths: installedPaths)
                },
                log: log
            )
        )
    }

    private func resolveSecretFileChanges(
        in request: ConfigureRuntimeRequest<Contracts.RuntimeNetworkMode>
    ) throws -> ConfigureRuntimeRequest<Contracts.RuntimeNetworkMode> {
        let useCase = ConfigureRuntimeUseCase<VMRuntimeConfig>()
        let changes = try request.changes.map { change in
            switch change {
            case .adminPasswordFile(let url):
                return try useCase.resolvedAdminPasswordChange(from: ConfigureRuntimeSecretFileInput(
                    path: url.path,
                    contents: actions.readSecretFile(url)
                ))
            default:
                return change
            }
        }
        return ConfigureRuntimeRequest(changes: changes, restart: request.restart)
    }

    private func executeConfigureEffects(_ plannedEffects: [ConfigureRuntimeEffect]) throws {
        for effect in plannedEffects {
            switch effect {
            case .createDirectory(let url, let withIntermediateDirectories):
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            case .resizeVMDiskIfNeeded(let diskGiB):
                try actions.resizeVMDiskIfNeeded(diskGiB)
            case .setInstalledProxyPort(let port):
                try actions.setInstalledProxyPort(port)
            case .setStartOnBoot(let enabled):
                try actions.setStartOnBoot(enabled)
            case .setSystemSleepPrevention(let enabled):
                try actions.setSystemSleepPrevention(enabled)
            case .setAutomaticBackupSchedule(let enabled, let scheduleTimes):
                try actions.setAutomaticBackupSchedule(enabled, scheduleTimes)
            case .setLogArchiveRetentionDays(let days):
                try updateRuntimeControlSettings { settings in
                    settings = RuntimeControlSettingsDocument(
                        logArchiveRetentionDays: days,
                        logArchiveMaximumGiB: settings.logArchiveMaximumGiB,
                        redisRelay: settings.redisRelay
                    )
                }
            case .setLogArchiveMaximumGiB(let gib):
                try updateRuntimeControlSettings { settings in
                    settings = RuntimeControlSettingsDocument(
                        logArchiveRetentionDays: settings.logArchiveRetentionDays,
                        logArchiveMaximumGiB: gib,
                        redisRelay: settings.redisRelay
                    )
                }
            case .writeRedisRelayConfiguration(let redisRelay):
                try writeRedisRelayConfiguration(redisRelay)
            case .reconcileGuestStackServices:
                try actions.reconcileGuestStackServices()
            case .restrictSecretFile(let url):
                try actions.restrictSecretFile(url)
            case .restartRuntimeServices:
                try actions.restartRuntimeServices()
            }
        }
    }

    private func updateRuntimeControlSettings(
        _ update: (inout RuntimeControlSettingsDocument) throws -> Void
    ) throws {
        var settings = try loadRuntimeControlSettings()
        try update(&settings)
        let data = try prettyJSONEncoder().encode(settings)
        try fileStore.createDirectory(
            at: installedPaths.runtimeControlSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileStore.writeData(data, to: installedPaths.runtimeControlSettings, options: .atomic)
    }

    private func writeRedisRelayConfiguration(
        _ settings: ConfigureRuntimeRedisRelaySettings
    ) throws {
        try RuntimeRedisRelayConfigurationWriter(
            installedPaths: installedPaths,
            fileStore: fileStore
        ).writeConfigured(settings)
    }

    private func loadRuntimeControlSettings() throws -> RuntimeControlSettingsDocument {
        let url = installedPaths.runtimeControlSettings
        switch fileStore.pathState(at: url) {
        case .file:
            break
        case .missing:
            return RuntimeControlSettingsDocument()
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "runtime control settings path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "runtime control settings path state is unexpected path=\(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: data)
    }

    private func loadVMDiskSizeGiB() throws -> Int {
        let url = installedPaths.vmDisk
        switch fileStore.pathState(at: url) {
        case .file:
            break
        case .missing:
            throw LauncherError.missingFile(url.path)
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "VM disk path inspection failed: \(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "VM disk path state is unexpected: \(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }
        let bytesPerGiB: UInt64 = 1024 * 1024 * 1024
        return max(Int((try fileStore.fileSize(url) + bytesPerGiB - 1) / bytesPerGiB), 1)
    }

    private func configureRuntimeContext() -> ConfigureRuntimeContext<Contracts.RuntimeNetworkMode> {
        ConfigureRuntimeContext(
            vmConfigURL: configURL,
            guestRuntimeConfigURL: installedPaths.guestRuntimeConfig,
            guestRuntimeSettingsURL: installedPaths.guestRuntimeSettings,
            minimumCPUCount: Constants.Defaults.minimumCPUCount,
            maximumAllowedCPUCount: maximumAllowedCPUCount,
            minimumMemoryGiB: Constants.Defaults.minimumMemoryGiB,
            maximumAllowedMemoryGiB: maximumAllowedMemoryGiB,
            memoryStepGiB: Constants.Defaults.memoryStepGiB,
            minimumDiskGiB: Constants.Defaults.minimumDiskGiB,
            maximumDiskGiB: Constants.Defaults.maximumDiskGiB,
            diskStepGiB: Constants.Defaults.diskStepGiB,
            maximumBackupRetentionCount: Constants.Defaults.maximumBackupRetentionCount,
            defaultPublicPort: Constants.Guest.publicPort,
            sharedNetworkMode: .shared,
            bridgedNetworkMode: .bridged,
            vitalFilesDirectoryTag: Constants.Defaults.vitalFilesDirectoryTag,
            vitalFilesDirectoryGuestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath
        )
    }

    private func loadGuestRuntimeConfig(from url: URL) throws -> GuestRuntimeConfigDocument {
        do {
            return try RuntimeGuestConfigDocumentReader.load(from: url, fileStore: fileStore)
        } catch RuntimeGuestConfigDocumentReadError.missingFile(let path) {
            throw LauncherError.missingFile(path)
        } catch RuntimeGuestConfigDocumentReadError.pathInspectionFailed(let path, let reason) {
            throw LauncherError.runtimeOperationFailed(
                "guest runtime config path inspection failed path=\(path) reason=\(reason)"
            )
        } catch RuntimeGuestConfigDocumentReadError.unexpectedPathState(let path, let state) {
            throw LauncherError.runtimeOperationFailed(
                "guest runtime config path state is unexpected path=\(path) state=\(state)"
            )
        }
    }

    private func loadGuestRuntimeSettings(from url: URL) throws -> GuestRuntimeSettingsDocument {
        switch fileStore.pathState(at: url) {
        case .file:
            break
        case .missing:
            throw LauncherError.missingFile(url.path)
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "guest runtime settings path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "guest runtime settings path state is unexpected path=\(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: data)
    }

    private func prettyJSONEncoder() -> JSONEncoder {
        VMRuntimeConfigComposition.prettyJSONEncoder()
    }

    private func configureRuntimeRequest(
        from command: RuntimeConfigureCommand
    ) throws -> ConfigureRuntimeRequest<Contracts.RuntimeNetworkMode> {
        ConfigureRuntimeRequest(
            changes: try command.changes.map { try configureRuntimeChange($0) },
            restart: command.restart
        )
    }

    private func configureRuntimeChange(
        _ change: RuntimeConfigureChange
    ) throws -> ConfigureRuntimeChange<Contracts.RuntimeNetworkMode> {
        switch change {
        case .cpu(let value):
            return .cpu(value)
        case .memoryGiB(let value):
            return .memoryGiB(value)
        case .diskGiB(let value):
            return .diskGiB(value)
        case .network(let value):
            return .network(value)
        case .bridgedInterface(let value):
            return .bridgedInterface(value)
        case .proxyPort(let value):
            return .proxyPort(value)
        case .vitalFilesDirectory(let value):
            return .vitalFilesDirectory(value)
        case .vitalServerURL(let value):
            return .vitalServerURL(value)
        case .remoteConsoleURL(let value):
            return .remoteConsoleURL(value)
        case .publicHost(let value):
            return .publicHost(value)
        case .publicPort(let value):
            return .publicPort(value)
        case .recorderIngressSendDataMode(let value):
            return .recorderIngressSendDataMode(value)
        case .recorderIngressSendDataReplayBatchSize(let value):
            return .recorderIngressSendDataReplayBatchSize(value)
        case .recorderIngressSendDataReplayMaxMiBPerSecond(let value):
            return .recorderIngressSendDataReplayMaxMiBPerSecond(value)
        case .recorderIngressSettingsFile(let value):
            return .recorderIngress(try recorderIngressSettings(from: value))
        case .containerMemoryLimitsEnabled(let value):
            return .containerMemoryLimitsEnabled(value)
        case .vitalServerContainerMemoryLimitMiB(let value):
            return .vitalServerContainerMemoryLimitMiB(value)
        case .recorderIngressContainerMemoryLimitMiB(let value):
            return .recorderIngressContainerMemoryLimitMiB(value)
        case .redisContainerMemoryLimitMiB(let value):
            return .redisContainerMemoryLimitMiB(value)
        case .adminPassword(let value):
            return .adminPassword(value)
        case .adminPasswordFile(let value):
            return .adminPasswordFile(value)
        case .startOnBoot(let value):
            return .startOnBoot(value)
        case .autoRecovery(let value):
            return .autoRecovery(value)
        case .preventSystemSleep(let value):
            return .preventSystemSleep(value)
        case .automaticBackup(let value):
            return .automaticBackup(value)
        case .backupScheduleTimes(let value):
            return .backupScheduleTimes(value)
        case .backupRetention(let value):
            return .backupRetention(value)
        case .logArchiveRetentionDays(let value):
            return .logArchiveRetentionDays(value)
        case .logArchiveMaximumGiB(let value):
            return .logArchiveMaximumGiB(value)
        case .redisRelaySettingsFile(let value):
            return .redisRelay(try redisRelaySettings(from: value))
        }
    }

    private func redisRelaySettings(from url: URL) throws -> ConfigureRuntimeRedisRelaySettings {
        let data = try actions.readSecretFile(url).data(using: .utf8) ?? Data()
        let settings = try JSONDecoder().decode(RuntimeRedisRelaySettings.self, from: data)
        return ConfigureRuntimeRedisRelaySettings(
            enabled: settings.enabled,
            target: ConfigureRuntimeRedisRelayTarget(
                url: settings.target.url,
                username: settings.target.username,
                password: settings.target.password,
                clearPassword: settings.target.clearPassword,
                passwordConfigured: settings.target.passwordConfigured,
                tls: settings.target.tls
            ),
            scope: ConfigureRuntimeRedisRelayScope(rawValue: settings.scope.rawValue) ?? .vitalReconstruction,
            includeRecorderNetworkContext: settings.includeRecorderNetworkContext,
            intervalSeconds: settings.intervalSeconds,
            scanCount: settings.scanCount
        )
    }

    private func recorderIngressSettings(from url: URL) throws -> RuntimeRecorderIngressSettings {
        let data = try actions.readSecretFile(url).data(using: .utf8) ?? Data()
        return try JSONDecoder().decode(RuntimeRecorderIngressSettings.self, from: data)
    }
}
