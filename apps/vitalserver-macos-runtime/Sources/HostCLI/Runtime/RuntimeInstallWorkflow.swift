import Foundation
import HostInfrastructure
import Core
import Contracts
import RuntimeWorkflow

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
    let freshInstallPreflight: () -> RuntimeFreshInstallPreflightDocument
    let installProvisionPayload: () -> RuntimeInstallProvisionPayloadDocument
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let writeRuntimeProgress: (RuntimeStepExecutionEvent) throws -> Void
    let rotateRuntimeLogs: () throws -> Void
    let requireFreeSpace: (URL, UInt64, String) throws -> Void
    let runRequired: (String, [String]) throws -> Void
    let runProcessToFile: (String, [String], URL) throws -> Void
    let writeInstalledRuntimeVersion: () throws -> Void
    let setStartOnBoot: (Bool) throws -> Void
    let startLaunchdService: (RuntimeManagedService) throws -> Void
    let cleanupHostProxyPortBeforeStart: () throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let restrictSecretFile: (URL) throws -> Void
    let log: (String) -> Void
}

struct RuntimeInstallWorkflowComposition {
    let context: RuntimeInstallWorkflowContext
    let operations: RuntimeInstallWorkflowOperations

    func install() throws {
        try runtimeInstallWorkflow().run(RuntimeInstallCommand(
            mode: .full,
            plan: RuntimeOperationPlans.install,
            completionStatus: .healthy,
            completionMessage: "runtime install completed"
        ))
    }

    func installProvision() throws {
        try runtimeInstallWorkflow().run(RuntimeInstallCommand(
            mode: .provision,
            plan: RuntimeOperationPlans.installProvision,
            completionStatus: .degraded,
            completionMessage: "runtime install provisioned; runtime services starting"
        ))
    }

    private func runtimeInstallWorkflow() -> RuntimeInstallWorkflow<InstallSettings> {
        RuntimeInstallWorkflow(
            readers: RuntimeInstallStateReaders(
                loadSettings: {
                    try InstallSettings.load(
                        defaultVitalFilesDirectory: context.installedPaths.vitalFilesDirectory.path,
                        fileStore: operations.fileStore
                    )
                },
                freshInstallPreflight: operations.freshInstallPreflight,
                provisionPayload: operations.installProvisionPayload
            ),
            effects: RuntimeInstallEffects(
                executeStep: { step, settings in
                    try runtimeInstallStepExecutor().execute(step, settings: settings)
                }
            ),
            writer: RuntimeInstallStateWriter(
                writeState: { state, mode, currentStep, message, blockers in
                    try RuntimeInstallStateStore(
                        url: context.installedPaths.runtimeInstallState,
                        fileStore: operations.fileStore,
                        now: operations.now
                    ).write(
                        state: state,
                        mode: mode,
                        currentStep: currentStep,
                        message: message,
                        blockers: blockers
                    )
                },
                writeStatus: operations.writeRuntimeStatus,
                writeProgress: operations.writeRuntimeProgress
            ),
            diagnostics: RuntimeInstallDiagnostics(log: operations.log),
            runtimeHomePath: { context.paths.home.path }
        )
    }

    private func runtimeInstallStepExecutor() -> RuntimeInstallStepExecutor<InstallSettings> {
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
            runtimeServiceRestartPolicy: { settings in
                RuntimeServiceRestartPolicy(
                    restartVM: settings.startAfterInstall,
                    restartGuestLogSync: settings.startAfterInstall,
                    restartProxy: settings.startAfterInstall,
                    restartWatchdog: settings.startAfterInstall
                )
            },
            waitForHealth: operations.waitForHealth,
            cleanupInstallSettings: {
                try cleanupInstallSettings()
            },
            log: operations.log
        )
    }

    private func runtimeInstallDirectoryPreparer() -> RuntimeInstallDirectoryPreparer<InstallSettings> {
        RuntimeInstallDirectoryPreparer(
            context: RuntimeInstallDirectoryPreparationContext(
                fixedDirectories: [
                    context.installedPaths.runtimeDirectory,
                    context.installedPaths.deployDirectory,
                    context.installedPaths.guestRunDirectory,
                    context.installedPaths.vrReleaseDirectory,
                    context.installedPaths.backupsDirectory,
                    context.installedPaths.redisBackupsDirectory,
                    context.installedPaths.productLogsDirectory,
                    context.installedPaths.centralRuntimeLogsDirectory,
                    context.installedPaths.centralGuestLogsDirectory,
                    context.installedPaths.logArchiveDirectory,
                    context.installedPaths.hostRunDirectory,
                    context.installedPaths.statusDirectory,
                    context.installedPaths.nginxLogsDirectory,
                ],
                staleGuestRunDocuments: [
                    context.installedPaths.vmIPFile,
                    context.installedPaths.runtimeState,
                    context.installedPaths.bootstrapResult,
                    context.installedPaths.updateActivationResult,
                    context.installedPaths.updateShutdownResult,
                    context.installedPaths.datastoreRepairResult,
                ],
                vitalFilesDirectory: { settings in
                    URL(fileURLWithPath: settings.vitalFilesDirectory)
                }
            ),
            operations: RuntimeInstallDirectoryPreparationOperations(
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                fileExists: { url in
                    operations.fileStore.fileExists(url)
                },
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                }
            )
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
        try RuntimeInstallVMDiskProvisioner(
            context: RuntimeInstallVMDiskProvisioningContext(
                rootfsBase: context.rootfsBase,
                vmDisk: context.vmDisk,
                gunzipExecutable: Constants.Commands.gunzip,
                truncateExecutable: Constants.Commands.truncate,
                freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes
            ),
            operations: RuntimeInstallVMDiskProvisioningOperations(
                fileExists: fileExists,
                fileSize: { url in
                    try operations.fileStore.fileSize(url)
                },
                requireFreeSpace: operations.requireFreeSpace,
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                },
                runProcessToFile: operations.runProcessToFile,
                moveItem: { source, destination in
                    try operations.fileStore.moveItem(at: source, to: destination)
                },
                runRequired: operations.runRequired,
                log: operations.log
            )
        ).provision(diskGiB: settings.diskGiB)
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
            context: RuntimeCloudInitSeedContext(
                runtimeDirectory: context.installedPaths.runtimeDirectory,
                seedImageName: Constants.BootAssets.cloudInit,
                seedVolumeName: "cidata",
                hdiutilExecutable: Constants.Commands.hdiutil
            ),
            operations: RuntimeCloudInitSeedOperations(
                directoryExists: directoryExists,
                fileExists: fileExists,
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                },
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                writeData: { data, url, options in
                    try operations.fileStore.writeData(data, to: url, options: options)
                },
                runRequired: operations.runRequired,
                instanceID: {
                    "tirosh-\(UUID().uuidString.lowercased())"
                }
            )
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
        try RuntimeInstallServiceStarter(
            operations: RuntimeInstallServiceStartOperations(
                startLaunchdService: operations.startLaunchdService,
                cleanupHostProxyPortBeforeStart: operations.cleanupHostProxyPortBeforeStart,
                log: operations.log
            )
        ).start(input: RuntimeInstallServiceStartInput(
            startAfterInstall: settings.startAfterInstall,
            preventSystemSleep: settings.preventSystemSleep
        ))
    }

    private func applyStartOnBootPolicy(_ settings: InstallSettings) throws {
        try RuntimeInstallStartOnBootPolicyApplier(
            context: RuntimeInstallStartOnBootPolicyContext(
                launchctlExecutable: Constants.Commands.launchctl
            ),
            operations: RuntimeInstallStartOnBootPolicyOperations(
                setStartOnBoot: operations.setStartOnBoot,
                runRequired: operations.runRequired
            )
        ).apply(input: RuntimeInstallStartOnBootPolicyInput(
            startOnBoot: settings.startOnBoot,
            preventSystemSleep: settings.preventSystemSleep
        ))
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

}
