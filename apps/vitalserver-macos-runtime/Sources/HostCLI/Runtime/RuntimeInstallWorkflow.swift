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
        try RuntimeInstallVMRuntimeConfigurator<VMRuntimeConfig>(
            context: RuntimeInstallVMRuntimeConfigurationContext(
                configURL: context.paths.config,
                requiredDirectories: [
                    context.installedPaths.runtimeDirectory,
                    context.installedPaths.vitalFilesDirectory,
                    context.installedPaths.vrReleaseDirectory,
                    context.installedPaths.hostRunDirectory,
                ]
            ),
            operations: RuntimeInstallVMRuntimeConfigurationOperations(
                createDirectory: { url, withIntermediateDirectories in
                    try operations.fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                fileExists: fileExists,
                loadConfig: { url in
                    try VMRuntimeConfig.load(from: url, fileStore: operations.fileStore)
                },
                defaultConfig: {
                    VMRuntimeConfig.default(paths: context.installedPaths)
                },
                ensureRuntimeDefaults: { config in
                    VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: context.installedPaths)
                },
                encodeConfig: { config in
                    try JSONEncoder.pretty.encode(config)
                },
                writeData: { data, url, options in
                    try operations.fileStore.writeData(data, to: url, options: options)
                }
            )
        ).configure(input: RuntimeInstallVMRuntimeConfigurationInput(
            cpuCount: settings.cpuCount,
            memoryGiB: settings.memoryGiB,
            networkMode: settings.networkMode,
            sharedNetworkMode: .shared,
            dataDirectoryPath: context.installedPaths.dataDirectory.path,
            sharedDirectoryTag: Constants.Defaults.sharedDirectoryTag,
            sharedDirectoryGuestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
            vitalFilesDirectoryPath: settings.vitalFilesDirectory,
            vitalFilesDirectoryTag: Constants.Defaults.vitalFilesDirectoryTag,
            vitalFilesDirectoryGuestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            preventSystemSleep: settings.preventSystemSleep
        ))
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
        try RuntimeInstallPermissionConfigurator(
            context: RuntimeInstallPermissionContext(
                runtimeHome: context.paths.home,
                nginxDirectory: context.productRoot.appendingPathComponent("nginx"),
                proxyLaunchDaemonPlist: RuntimeManagedService.proxy.launchDaemonPlist,
                serviceLaunchDaemonPlists: [
                    RuntimeManagedService.vm.launchDaemonPlist,
                    RuntimeManagedService.proxy.launchDaemonPlist,
                    RuntimeManagedService.guestLogSync.launchDaemonPlist,
                    RuntimeManagedService.sleepPrevention.launchDaemonPlist,
                    RuntimeManagedService.watchdog.launchDaemonPlist,
                ],
                chownExecutable: Constants.Commands.chown,
                chmodExecutable: Constants.Commands.chmod,
                plistBuddyExecutable: Constants.Commands.plistBuddy
            ),
            operations: RuntimeInstallPermissionOperations(
                runRequired: operations.runRequired
            )
        ).configure(input: RuntimeInstallPermissionInput(
            proxyPort: settings.proxyPort
        ))
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
        try RuntimeInstallSettingsCleaner(
            context: RuntimeInstallSettingsCleanupContext(
                settingsFile: URL(fileURLWithPath: InstallSettings.defaultSettingsPath)
            ),
            operations: RuntimeInstallSettingsCleanupOperations(
                fileExists: fileExists,
                removeItem: { url in
                    try operations.fileStore.removeItem(at: url)
                }
            )
        ).cleanup()
    }

    private func fileExists(_ url: URL) -> Bool {
        operations.fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        operations.fileStore.directoryExists(url)
    }

}
