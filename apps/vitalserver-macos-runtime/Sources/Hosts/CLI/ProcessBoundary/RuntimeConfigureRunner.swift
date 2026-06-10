import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
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
                command.configureRuntimeRequest,
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
        in request: ConfigureRuntimeRequest<RuntimeNetworkMode>
    ) throws -> ConfigureRuntimeRequest<RuntimeNetworkMode> {
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
            case .restrictSecretFile(let url):
                try actions.restrictSecretFile(url)
            case .restartRuntimeServices:
                try actions.restartRuntimeServices()
            }
        }
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

    private func configureRuntimeContext() -> ConfigureRuntimeContext<RuntimeNetworkMode> {
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
