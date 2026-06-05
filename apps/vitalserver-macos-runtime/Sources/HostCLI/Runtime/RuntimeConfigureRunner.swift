import Contracts
import Core
import Foundation
import HostInfrastructure
import RuntimeWorkflow

struct RuntimeConfigureActions {
    var resizeVMDiskIfNeeded: (Int) throws -> Void
    var setInstalledProxyPort: (Int) throws -> Void
    var readSecretFile: (URL) throws -> String
    var restrictSecretFile: (URL) throws -> Void
    var setStartOnBoot: (Bool) throws -> Void
    var setSystemSleepPrevention: (Bool) throws -> Void
    var restartRuntimeServices: () throws -> Void
}

struct RuntimeConfigureResult: Equatable {
    let restart: Bool
}

struct RuntimeConfigureRunner {
    private let installedPaths: InstalledRuntimePaths
    private let configURL: URL
    private let fileStore: RuntimeFileStore
    private let actions: RuntimeConfigureActions
    private let log: (String) -> Void

    init(
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

    func configure(_ command: RuntimeConfigureCommand) throws -> RuntimeConfigureResult {
        do {
            let result = try runtimeConfigureWorkflow().configure(command.workflowInput)
            return RuntimeConfigureResult(restart: result.restart)
        } catch RuntimeConfigureWorkflowError.invalidArgument(let message) {
            throw LauncherError.missingArgument(message)
        }
    }

    private func runtimeConfigureWorkflow() -> RuntimeConfigureWorkflow<VMRuntimeConfig> {
        RuntimeConfigureWorkflow(
            context: RuntimeConfigureWorkflowContext(
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
            ),
            operations: RuntimeConfigureWorkflowOperations(
                loadVMConfig: { url in
                    try VMRuntimeConfig.load(from: url, fileStore: fileStore)
                },
                loadGuestRuntimeConfig: { url in
                    try GuestRuntimeConfigDocument.load(from: url, fileStore: fileStore)
                },
                encodeVMConfig: { config in
                    try JSONEncoder.pretty.encode(config)
                },
                encodeGuestRuntimeConfig: { config in
                    try JSONEncoder.pretty.encode(config)
                },
                encodeGuestRuntimeSettings: { settings in
                    try JSONEncoder.pretty.encode(settings)
                },
                writeData: { data, url, options in
                    try fileStore.writeData(data, to: url, options: options)
                },
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
                    VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: installedPaths)
                },
                log: log
            )
        )
    }
}

private extension RuntimeConfigureCommand {
    var workflowInput: RuntimeConfigureWorkflowInput<NetworkMode> {
        RuntimeConfigureWorkflowInput(
            changes: changes.map(\.workflowChange),
            restart: restart
        )
    }
}

private extension RuntimeConfigureChange {
    var workflowChange: RuntimeConfigureWorkflowChange<NetworkMode> {
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
