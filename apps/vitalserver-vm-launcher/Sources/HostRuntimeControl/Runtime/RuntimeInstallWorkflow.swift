import Foundation
import HostRuntimeInfrastructure
import RuntimeCore

struct RuntimeInstallWorkflow {
    let paths: LauncherPaths
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore
    let now: () -> Date
    let productRoot: URL
    let logsDirectory: URL
    let rootfsBase: URL
    let vmDisk: URL
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let writeRuntimeProgress: (RuntimeStepExecutionEvent) throws -> Void
    let rotateRuntimeLogs: () throws -> Void
    let requireFreeSpace: (URL, UInt64, String) throws -> Void
    let runRequired: (String, [String]) throws -> Void
    let runProcessToFile: (String, [String], URL) throws -> Void
    let writeInstalledRuntimeVersion: () throws -> Void
    let setStartOnBoot: (Bool) throws -> Void
    let startLaunchdService: (String) -> Void
    let restrictSecretFile: (URL) throws -> Void
    let log: (String) -> Void

    func install() throws {
        try runtimeInstallRunner().run()
    }

    private func runtimeInstallRunner() -> RuntimeInstallRunner {
        RuntimeInstallRunner(
            loadSettings: {
                try InstallSettings.load(
                    defaultVitalFilesDirectory: installedPaths.vitalFilesDirectory.path,
                    fileStore: fileStore
                )
            },
            executeStep: { step, settings in
                try runtimeInstallStepExecutor().execute(step, settings: settings)
            },
            writeStatus: writeRuntimeStatus,
            writeProgress: writeRuntimeProgress,
            runtimeHomePath: { paths.home.path },
            log: log
        )
    }

    private func runtimeInstallStepExecutor() -> RuntimeInstallStepExecutor {
        RuntimeInstallStepExecutor(
            prepareInstallDirectories: { settings in
                try runtimeInstallDirectoryPreparer().prepare(settings: settings)
            },
            rotateRuntimeLogs: rotateRuntimeLogs,
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
            writeInstalledRuntimeVersion: writeInstalledRuntimeVersion,
            configureInstalledPermissions: { settings in
                try configureInstalledPermissions(settings)
            },
            startInstalledServices: { settings in
                try startInstalledServices(settings)
            },
            applyStartOnBootPolicy: { settings in
                try applyStartOnBootPolicy(settings)
            },
            cleanupInstallSettings: {
                try cleanupInstallSettings()
            },
            log: log
        )
    }

    private func runtimeInstallDirectoryPreparer() -> RuntimeInstallDirectoryPreparer {
        RuntimeInstallDirectoryPreparer(
            installedPaths: installedPaths,
            fileStore: fileStore,
            now: now
        )
    }

    private func runtimeGuestConfigWriter() -> RuntimeGuestConfigWriter {
        RuntimeGuestConfigWriter(
            installedPaths: installedPaths,
            fileStore: fileStore,
            restrictSecretFile: restrictSecretFile
        )
    }

    private func configureDeployEnvironment(_ settings: InstallSettings) throws {
        try runtimeGuestConfigWriter().writeInstallConfig(settings: settings)
    }

    private func prepareInstalledExecutables() throws {
        for path in [
            Constants.InstallPaths.vmBin,
            Constants.InstallPaths.proxyRun,
            installedPaths.nginxExecutable.path,
        ] {
            try runRequired(Constants.Commands.chmod, ["0755", path])
        }
    }

    private func provisionVMDisk(_ settings: InstallSettings) throws {
        if !fileExists(vmDisk), fileExists(rootfsBase) {
            try requireFreeSpace(
                vmDisk.deletingLastPathComponent(),
                (try fileSize(rootfsBase) * 6) + Constants.Runtime.freeSpaceMarginBytes,
                "provision-vm-disk"
            )
            let temporary = vmDisk.deletingLastPathComponent().appendingPathComponent(".\(vmDisk.lastPathComponent).tmp")
            if fileExists(temporary) {
                try fileStore.removeItem(at: temporary)
            }
            try runProcessToFile(
                Constants.Commands.gunzip,
                ["-c", rootfsBase.path],
                temporary
            )
            try fileStore.moveItem(at: temporary, to: vmDisk)
            log("created vm disk path=\(vmDisk.path) source=\(rootfsBase.lastPathComponent)")
        }
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(rootfsBase.path)
        }
        try runRequired(Constants.Commands.truncate, ["-s", "\(settings.diskGiB)G", vmDisk.path])
    }

    private func configureInstalledVMRuntime(_ settings: InstallSettings) throws {
        try fileStore.createDirectory(
            at: installedPaths.runtimeDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.vitalFilesDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.vrReleaseDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.hostRunDirectory,
            withIntermediateDirectories: true
        )

        var config: VMRuntimeConfig
        if fileExists(paths.config) {
            config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        } else {
            config = VMRuntimeConfig.default(paths: installedPaths)
        }
        config.cpuCount = settings.cpuCount
        config.memoryMiB = UInt64(settings.memoryGiB * 1024)
        config.network.mode = settings.networkMode
        if settings.networkMode == .shared {
            config.network.bridgedInterface = nil
        }
        config.sharedDirectory = SharedDirectoryConfig(
            hostPath: installedPaths.dataDirectory.path,
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
        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: installedPaths)
        let encoded = try JSONEncoder.pretty.encode(config)
        try fileStore.createDirectory(at: paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(encoded, to: paths.config, options: [])
    }

    private func createCloudInitSeed(_ settings: InstallSettings) throws {
        try RuntimeCloudInitSeedWriter(
            installedPaths: installedPaths,
            fileStore: fileStore,
            runRequired: runRequired
        ).create(hostname: settings.vmHostname)
    }

    private func configureInstalledPermissions(_ settings: InstallSettings) throws {
        try runRequired(Constants.Commands.chown, ["-R", "root:wheel", paths.home.path])
        try runRequired(Constants.Commands.chown, ["-R", "root:wheel", "\(productRoot.path)/nginx"])
        try runRequired(
            Constants.Commands.plistBuddy,
            [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(settings.proxyPort)",
                launchDaemonPlist(Constants.Launchd.proxyService),
            ]
        )
        for plist in [
            launchDaemonPlist(Constants.Launchd.vmService),
            launchDaemonPlist(Constants.Launchd.proxyService),
            launchDaemonPlist(Constants.Launchd.watchdogService),
        ] {
            try runRequired(Constants.Commands.chmod, ["0644", plist])
            try runRequired(Constants.Commands.chown, ["root:wheel", plist])
        }
    }

    private func startInstalledServices(_ settings: InstallSettings) throws {
        guard settings.startAfterInstall else {
            log("start after install disabled")
            return
        }
        startLaunchdService(Constants.Launchd.vmService)
        startLaunchdService(Constants.Launchd.proxyService)
        startLaunchdService(Constants.Launchd.watchdogService)
    }

    private func applyStartOnBootPolicy(_ settings: InstallSettings) throws {
        try setStartOnBoot(settings.startOnBoot)
    }

    private func cleanupInstallSettings() throws {
        let settingsFile = URL(fileURLWithPath: InstallSettings.defaultSettingsPath)
        if fileExists(settingsFile) {
            try fileStore.removeItem(at: settingsFile)
        }
    }

    private func launchDaemonPlist(_ label: String) -> String {
        "\(Constants.InstallPaths.launchDaemons)/\(label).plist"
    }

    private func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }
}
