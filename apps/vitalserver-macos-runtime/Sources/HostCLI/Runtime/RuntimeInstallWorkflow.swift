import Foundation
import HostInfrastructure
import Core
import Contracts

struct RuntimeInstallWorkflowContext {
    let paths: LauncherPaths
    let installedPaths: InstalledRuntimePaths
    let productRoot: URL
    let rootfsBase: URL
    let vmDisk: URL
}

struct RuntimeInstallWorkflowOperations {
    let fileStore: RuntimeFileStore
    let now: () -> Date
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let writeRuntimeProgress: (RuntimeStepExecutionEvent) throws -> Void
    let rotateRuntimeLogs: () throws -> Void
    let requireFreeSpace: (URL, UInt64, String) throws -> Void
    let runRequired: (String, [String]) throws -> Void
    let runProcessToFile: (String, [String], URL) throws -> Void
    let writeInstalledRuntimeVersion: () throws -> Void
    let setStartOnBoot: (Bool) throws -> Void
    let startLaunchdService: (RuntimeManagedService) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let restrictSecretFile: (URL) throws -> Void
    let log: (String) -> Void
}

struct RuntimeInstallWorkflow {
    let context: RuntimeInstallWorkflowContext
    let operations: RuntimeInstallWorkflowOperations

    func install() throws {
        try runtimeInstallRunner().run()
    }

    private func runtimeInstallRunner() -> RuntimeInstallRunner {
        RuntimeInstallRunner(
            loadSettings: {
                try InstallSettings.load(
                    defaultVitalFilesDirectory: context.installedPaths.vitalFilesDirectory.path,
                    fileStore: operations.fileStore
                )
            },
            executeStep: { step, settings in
                try runtimeInstallStepExecutor().execute(step, settings: settings)
            },
            writeStatus: operations.writeRuntimeStatus,
            writeProgress: operations.writeRuntimeProgress,
            runtimeHomePath: { context.paths.home.path },
            log: operations.log
        )
    }

    private func runtimeInstallStepExecutor() -> RuntimeInstallStepExecutor {
        RuntimeInstallStepExecutor(
            prepareInstallDirectories: { settings in
                try runtimeInstallDirectoryPreparer().prepare(settings: settings)
            },
            rotateRuntimeLogs: operations.rotateRuntimeLogs,
            configureDeployEnvironment: { settings in
                try configureDeployEnvironment(settings)
            },
            prepareInstalledExecutables: {
                try prepareInstalledExecutables()
            },
            provisionVMDisk: { settings in
                try provisionVMDisk(settings)
            },
            configureInstalledVMRuntime: { settings in
                try configureInstalledVMRuntime(settings)
            },
            createCloudInitSeed: { settings in
                try createCloudInitSeed(settings)
            },
            writeInstalledRuntimeVersion: operations.writeInstalledRuntimeVersion,
            configureInstalledPermissions: { settings in
                try configureInstalledPermissions(settings)
            },
            startInstalledServices: { settings in
                try startInstalledServices(settings)
            },
            applyStartOnBootPolicy: { settings in
                try applyStartOnBootPolicy(settings)
            },
            waitForHealth: operations.waitForHealth,
            cleanupInstallSettings: {
                try cleanupInstallSettings()
            },
            log: operations.log
        )
    }

    private func runtimeInstallDirectoryPreparer() -> RuntimeInstallDirectoryPreparer {
        RuntimeInstallDirectoryPreparer(
            installedPaths: context.installedPaths,
            fileStore: operations.fileStore
        )
    }

    private func runtimeGuestConfigWriter() -> RuntimeGuestConfigWriter {
        RuntimeGuestConfigWriter(
            installedPaths: context.installedPaths,
            fileStore: operations.fileStore,
            restrictSecretFile: operations.restrictSecretFile
        )
    }

    private func configureDeployEnvironment(_ settings: InstallSettings) throws {
        try runtimeGuestConfigWriter().writeInstallConfig(settings: settings)
    }

    private func prepareInstalledExecutables() throws {
        for path in [
            Constants.InstallPaths.vmBin,
            Constants.InstallPaths.proxyRun,
            context.installedPaths.nginxExecutable.path,
        ] {
            try operations.runRequired(Constants.Commands.chmod, ["0755", path])
        }
    }

    private func provisionVMDisk(_ settings: InstallSettings) throws {
        if !fileExists(context.vmDisk), fileExists(context.rootfsBase) {
            try operations.requireFreeSpace(
                context.vmDisk.deletingLastPathComponent(),
                (try fileSize(context.rootfsBase) * 6) + Constants.Runtime.freeSpaceMarginBytes,
                "provision-vm-disk"
            )
            let temporary = context.vmDisk.deletingLastPathComponent().appendingPathComponent(".\(context.vmDisk.lastPathComponent).tmp")
            if fileExists(temporary) {
                try operations.fileStore.removeItem(at: temporary)
            }
            try operations.runProcessToFile(
                Constants.Commands.gunzip,
                ["-c", context.rootfsBase.path],
                temporary
            )
            try operations.fileStore.moveItem(at: temporary, to: context.vmDisk)
            operations.log("created vm disk path=\(context.vmDisk.path) source=\(context.rootfsBase.lastPathComponent)")
        }
        guard fileExists(context.vmDisk) else {
            throw LauncherError.missingFile(context.rootfsBase.path)
        }
        try operations.runRequired(Constants.Commands.truncate, ["-s", "\(settings.diskGiB)G", context.vmDisk.path])
    }

    private func configureInstalledVMRuntime(_ settings: InstallSettings) throws {
        try operations.fileStore.createDirectory(
            at: context.installedPaths.runtimeDirectory,
            withIntermediateDirectories: true
        )
        try operations.fileStore.createDirectory(
            at: context.installedPaths.vitalFilesDirectory,
            withIntermediateDirectories: true
        )
        try operations.fileStore.createDirectory(
            at: context.installedPaths.vrReleaseDirectory,
            withIntermediateDirectories: true
        )
        try operations.fileStore.createDirectory(
            at: context.installedPaths.hostRunDirectory,
            withIntermediateDirectories: true
        )

        var config: VMRuntimeConfig
        if fileExists(context.paths.config) {
            config = try VMRuntimeConfig.load(from: context.paths.config, fileStore: operations.fileStore)
        } else {
            config = VMRuntimeConfig.default(paths: context.installedPaths)
        }
        config.cpuCount = settings.cpuCount
        config.memoryMiB = UInt64(settings.memoryGiB * 1024)
        config.network.mode = settings.networkMode
        if settings.networkMode == .shared {
            config.network.bridgedInterface = nil
        }
        config.sharedDirectory = SharedDirectoryConfig(
            hostPath: context.installedPaths.dataDirectory.path,
            tag: Constants.Defaults.sharedDirectoryTag,
            guestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
            readOnly: false
        )
        config.vitalFilesDirectory = SharedDirectoryConfig(
            hostPath: settings.vitalFilesDirectory,
            tag: Constants.Defaults.vitalFilesDirectoryTag,
            guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            readOnly: false
        )
        config.preventSystemSleep = settings.preventSystemSleep
        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: context.installedPaths)
        let encoded = try JSONEncoder.pretty.encode(config)
        try operations.fileStore.createDirectory(at: context.paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try operations.fileStore.writeData(encoded, to: context.paths.config, options: [])
    }

    private func createCloudInitSeed(_ settings: InstallSettings) throws {
        try RuntimeCloudInitSeedWriter(
            installedPaths: context.installedPaths,
            fileStore: operations.fileStore,
            runRequired: operations.runRequired
        ).create(hostname: settings.vmHostname)
    }

    private func configureInstalledPermissions(_ settings: InstallSettings) throws {
        try operations.runRequired(Constants.Commands.chown, ["-R", "root:wheel", context.paths.home.path])
        try operations.runRequired(Constants.Commands.chown, ["-R", "root:wheel", "\(context.productRoot.path)/nginx"])
        try operations.runRequired(
            Constants.Commands.plistBuddy,
            [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(settings.proxyPort)",
                RuntimeManagedService.proxy.launchDaemonPlist,
            ]
        )
        for plist in [
            RuntimeManagedService.vm.launchDaemonPlist,
            RuntimeManagedService.proxy.launchDaemonPlist,
            RuntimeManagedService.guestLogSync.launchDaemonPlist,
            RuntimeManagedService.sleepPrevention.launchDaemonPlist,
            RuntimeManagedService.watchdog.launchDaemonPlist,
        ] {
            try operations.runRequired(Constants.Commands.chmod, ["0644", plist])
            try operations.runRequired(Constants.Commands.chown, ["root:wheel", plist])
        }
    }

    private func startInstalledServices(_ settings: InstallSettings) throws {
        guard settings.startAfterInstall else {
            operations.log("start after install disabled")
            return
        }
        if settings.preventSystemSleep {
            try operations.startLaunchdService(.sleepPrevention)
        }
        for service in RuntimeManagedService.startOrder {
            try operations.startLaunchdService(service)
        }
    }

    private func applyStartOnBootPolicy(_ settings: InstallSettings) throws {
        try operations.setStartOnBoot(settings.startOnBoot)
        let action = settings.preventSystemSleep && settings.startOnBoot ? "enable" : "disable"
        try operations.runRequired(Constants.Commands.launchctl, [action, "system/\(RuntimeManagedService.sleepPrevention.label)"])
    }

    private func cleanupInstallSettings() throws {
        let settingsFile = URL(fileURLWithPath: InstallSettings.defaultSettingsPath)
        if fileExists(settingsFile) {
            try operations.fileStore.removeItem(at: settingsFile)
        }
    }

    private func fileExists(_ url: URL) -> Bool {
        operations.fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        operations.fileStore.directoryExists(url)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try operations.fileStore.fileSize(url)
    }
}
