import Application
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

public struct RuntimeConfigureActions {
    public var resizeVMDiskIfNeeded: (Int) throws -> Void
    public var setInstalledProxyPort: (Int) throws -> Void
    public var readSecretFile: (URL) throws -> String
    public var restrictSecretFile: (URL) throws -> Void
    public var setStartOnBoot: (Bool) throws -> Void
    public var setSystemSleepPrevention: (Bool) throws -> Void
    public var restartRuntimeServices: () throws -> Void

    public init(
        resizeVMDiskIfNeeded: @escaping (Int) throws -> Void,
        setInstalledProxyPort: @escaping (Int) throws -> Void,
        readSecretFile: @escaping (URL) throws -> String,
        restrictSecretFile: @escaping (URL) throws -> Void,
        setStartOnBoot: @escaping (Bool) throws -> Void,
        setSystemSleepPrevention: @escaping (Bool) throws -> Void,
        restartRuntimeServices: @escaping () throws -> Void
    ) {
        self.resizeVMDiskIfNeeded = resizeVMDiskIfNeeded
        self.setInstalledProxyPort = setInstalledProxyPort
        self.readSecretFile = readSecretFile
        self.restrictSecretFile = restrictSecretFile
        self.setStartOnBoot = setStartOnBoot
        self.setSystemSleepPrevention = setSystemSleepPrevention
        self.restartRuntimeServices = restartRuntimeServices
    }
}

public struct RuntimeConfigureResult: Equatable {
    public let restart: Bool

    public init(restart: Bool) {
        self.restart = restart
    }
}

public struct RuntimeConfigureCompositionContext {
    let installedPaths: InstalledRuntimePaths
    let configURL: URL

    public init(
        installedPaths: InstalledRuntimePaths,
        configURL: URL
    ) {
        self.installedPaths = installedPaths
        self.configURL = configURL
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
                restartRuntimeServices: operations.restartRuntimeServices
            ),
            log: operations.log
        )
    }
}

public struct RuntimeConfigureRunner {
    private let installedPaths: InstalledRuntimePaths
    private let configURL: URL
    private let fileStore: RuntimeFileStore
    private let actions: RuntimeConfigureActions
    private let log: (String) -> Void

    public init(
        installedPaths: InstalledRuntimePaths,
        configURL: URL,
        fileStore: RuntimeFileStore,
        actions: RuntimeConfigureActions,
        log: @escaping (String) -> Void
    ) {
        self.installedPaths = installedPaths
        self.configURL = configURL
        self.fileStore = fileStore
        self.actions = actions
        self.log = log
    }

    public func configure(_ command: RuntimeConfigureCommand) throws -> RuntimeConfigureResult {
        do {
            let result = try runtimeConfigureWorkflow().configure(
                command.configureRuntimeRequest,
                context: configureRuntimeContext()
            )
            return RuntimeConfigureResult(restart: result.restart)
        } catch ConfigureRuntimeError.invalidArgument(let message) {
            throw LauncherError.missingArgument(message)
        }
    }

    private func runtimeConfigureWorkflow() -> RuntimeConfigureWorkflow<VMRuntimeConfig> {
        RuntimeConfigureWorkflow(
            readers: RuntimeConfigureStateReaders(
                loadVMConfig: { url in
                    try VMRuntimeConfigComposition.load(from: url, fileStore: fileStore)
                },
                loadGuestRuntimeConfig: { url in
                    try loadGuestRuntimeConfig(from: url)
                }
            ),
            writer: RuntimeConfigureDocumentWriter(
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
            effects: RuntimeConfigureEffects(
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                resizeVMDiskIfNeeded: actions.resizeVMDiskIfNeeded,
                setInstalledProxyPort: actions.setInstalledProxyPort,
                readSecretFile: actions.readSecretFile,
                restrictSecretFile: actions.restrictSecretFile,
                setStartOnBoot: actions.setStartOnBoot,
                setSystemSleepPrevention: actions.setSystemSleepPrevention,
                restartRuntimeServices: actions.restartRuntimeServices,
                ensureRuntimeDefaults: { config in
                    VMRuntimeConfigComposition.ensureRuntimeDefaults(&config, paths: installedPaths)
                },
                log: log
            )
        )
    }

    private func configureRuntimeContext() -> ConfigureRuntimeContext<RuntimeNetworkMode> {
        ConfigureRuntimeContext(
            vmConfigURL: configURL,
            guestRuntimeConfigURL: installedPaths.guestRuntimeConfig,
            guestRuntimeSettingsURL: installedPaths.guestRuntimeSettings,
            minimumCPUCount: Constants.Defaults.minimumCPUCount,
            maximumAllowedCPUCount: Constants.Defaults.maximumAllowedCPUCount,
            minimumMemoryGiB: Constants.Defaults.minimumMemoryGiB,
            maximumAllowedMemoryGiB: Constants.Defaults.maximumAllowedMemoryGiB,
            memoryStepGiB: Constants.Defaults.memoryStepGiB,
            minimumDiskGiB: Constants.Defaults.minimumDiskGiB,
            maximumDiskGiB: Constants.Defaults.maximumDiskGiB,
            diskStepGiB: Constants.Defaults.diskStepGiB,
            maximumRedisBackupRetentionCount: Constants.Defaults.maximumRedisBackupRetentionCount,
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
        }
    }

    private func prettyJSONEncoder() -> JSONEncoder {
        VMRuntimeConfigComposition.prettyJSONEncoder()
    }
}

private extension RuntimeConfigureCommand {
    var configureRuntimeRequest: ConfigureRuntimeRequest<RuntimeNetworkMode> {
        ConfigureRuntimeRequest(
            changes: changes.map(\.configureRuntimeChange),
            restart: restart
        )
    }
}

private extension RuntimeConfigureChange {
    var configureRuntimeChange: ConfigureRuntimeChange<RuntimeNetworkMode> {
        switch self {
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
        case .redisBackupRetention(let value):
            return .redisBackupRetention(value)
        }
    }
}
