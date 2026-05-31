import Foundation
import Core
import Contracts
import HostInfrastructure

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
        var vmConfig = try VMRuntimeConfig.load(from: configURL, fileStore: fileStore)
        let runtimeConfigURL = installedPaths.guestRuntimeConfig
        var guestConfig = try GuestRuntimeConfigDocument.load(from: runtimeConfigURL, fileStore: fileStore)

        for change in command.changes {
            try apply(change, vmConfig: &vmConfig, guestConfig: &guestConfig)
        }

        try validate(vmConfig)
        VMRuntimeConfig.ensureRuntimeDefaults(&vmConfig, paths: installedPaths)
        try fileStore.writeData(try JSONEncoder.pretty.encode(vmConfig), to: configURL, options: .atomic)
        try fileStore.writeData(try JSONEncoder.pretty.encode(guestConfig), to: runtimeConfigURL, options: .atomic)
        try fileStore.writeData(
            try JSONEncoder.pretty.encode(GuestRuntimeSettingsDocument(runtimeConfig: guestConfig)),
            to: installedPaths.guestRuntimeSettings,
            options: .atomic
        )
        try actions.restrictSecretFile(runtimeConfigURL)
        log("runtime configuration updated restart=\(command.restart)")

        if command.restart {
            try actions.restartRuntimeServices()
        }
        return RuntimeConfigureResult(restart: command.restart)
    }

    private func apply(
        _ change: RuntimeConfigureChange,
        vmConfig: inout VMRuntimeConfig,
        guestConfig: inout GuestRuntimeConfigDocument
    ) throws {
        switch change {
        case .cpu(let cpu):
            guard cpu >= Constants.Defaults.minimumCPUCount,
                  cpu <= Constants.Defaults.maximumAllowedCPUCount else {
                throw LauncherError.missingArgument(
                    "--cpu must be between \(Constants.Defaults.minimumCPUCount) and \(Constants.Defaults.maximumAllowedCPUCount)"
                )
            }
            vmConfig.cpuCount = cpu
        case .memoryGiB(let memoryGiB):
            guard stride(
                    from: Constants.Defaults.minimumMemoryGiB,
                    through: Constants.Defaults.maximumAllowedMemoryGiB,
                    by: Constants.Defaults.memoryStepGiB
                  ).contains(Int(memoryGiB)) else {
                throw LauncherError.missingArgument(
                    "--memory-gib must be between \(Constants.Defaults.minimumMemoryGiB) and \(Constants.Defaults.maximumAllowedMemoryGiB) in \(Constants.Defaults.memoryStepGiB) GiB steps"
                )
            }
            vmConfig.memoryMiB = memoryGiB * 1024
        case .diskGiB(let diskGiB):
            guard stride(
                    from: Constants.Defaults.minimumDiskGiB,
                    through: Constants.Defaults.maximumDiskGiB,
                    by: Constants.Defaults.diskStepGiB
                  ).contains(diskGiB) else {
                throw LauncherError.missingArgument(
                    "--disk-gib must be between \(Constants.Defaults.minimumDiskGiB) and \(Constants.Defaults.maximumDiskGiB) in \(Constants.Defaults.diskStepGiB) GiB steps"
                )
            }
            try actions.resizeVMDiskIfNeeded(diskGiB)
        case .network(let mode):
            vmConfig.network.mode = mode
            if mode == .shared {
                vmConfig.network.bridgedInterface = nil
            }
        case .bridgedInterface(let value):
            guard RuntimeTextValidator.isSingleLine(value), !value.isEmpty else {
                throw LauncherError.missingArgument("--bridged-interface must not be empty or contain newlines")
            }
            vmConfig.network.bridgedInterface = value
        case .proxyPort(let port):
            guard (1...65_535).contains(port) else {
                throw LauncherError.missingArgument("--proxy-port must be between 1 and 65535")
            }
            try actions.setInstalledProxyPort(port)
        case .vitalFilesDirectory(let url):
            try fileStore.createDirectory(at: url, withIntermediateDirectories: true)
            vmConfig.vitalFilesDirectory = SharedDirectoryConfig(
                hostPath: url.path,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            )
            guestConfig.vitalFilesDirectory = Constants.Defaults.vitalFilesDirectoryGuestMountPath
        case .publicHost(let value):
            guard RuntimeTextValidator.isSingleLine(value) else {
                throw LauncherError.missingArgument("--public-host must not contain newlines")
            }
            guestConfig.publicHost = value
        case .publicPort(let port):
            guard (1...65_535).contains(port) else {
                throw LauncherError.missingArgument("--public-port must be between 1 and 65535")
            }
            guestConfig.publicPort = port
        case .adminPassword(let value):
            guard !value.isEmpty, RuntimeTextValidator.isSingleLine(value) else {
                throw LauncherError.missingArgument("--admin-password must not be empty or contain newlines")
            }
            guestConfig.adminPassword = value
        case .adminPasswordFile(let url):
            let password = try actions.readSecretFile(url)
            guard !password.isEmpty, RuntimeTextValidator.isSingleLine(password) else {
                throw LauncherError.missingArgument("--admin-password-file must contain a non-empty single-line password")
            }
            guestConfig.adminPassword = password
        case .startOnBoot(let enabled):
            try actions.setStartOnBoot(enabled)
        case .autoRecovery(let enabled):
            vmConfig.autoRecoveryEnabled = enabled
        case .preventSystemSleep(let enabled):
            vmConfig.preventSystemSleep = enabled
            try actions.setSystemSleepPrevention(enabled)
        case .redisBackupRetention(let count):
            guard (1...Constants.Defaults.maximumRedisBackupRetentionCount).contains(count) else {
                throw LauncherError.missingArgument(
                    "--redis-backup-retention must be between 1 and \(Constants.Defaults.maximumRedisBackupRetentionCount)"
                )
            }
            guestConfig.redisBackupRetentionCount = count
        }
    }

    private func validate(_ vmConfig: VMRuntimeConfig) throws {
        if vmConfig.network.mode == .bridged,
           vmConfig.network.bridgedInterface?.isEmpty != false {
            throw LauncherError.missingArgument("--bridged-interface is required when --network bridged")
        }
    }
}
