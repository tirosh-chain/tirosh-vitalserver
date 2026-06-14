import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func runtimeInstallDirectoryPreparer() -> RuntimeInstallDirectoryPreparer<RuntimeInstallSettings> {
        RuntimeInstallDirectoryPreparer(
            context: RuntimeInstallDirectoryPreparationContext(
                fixedDirectories: [
                    installedPaths.runtimeDirectory,
                    installedPaths.deployDirectory,
                    installedPaths.guestRunDirectory,
                    installedPaths.vrReleaseDirectory,
                    installedPaths.backupsDirectory,
                    installedPaths.vitalServerHelperBackupsDirectory,
                    installedPaths.redisOnlyBackupsDirectory,
                    installedPaths.updateRollbackBackupsDirectory,
                    installedPaths.vmDiskRepairBackupsDirectory,
                    installedPaths.redisBackupsDirectory,
                    installedPaths.productLogsDirectory,
                    installedPaths.centralRuntimeLogsDirectory,
                    installedPaths.centralGuestLogsDirectory,
                    installedPaths.logArchiveDirectory,
                    installedPaths.hostRunDirectory,
                    installedPaths.statusDirectory,
                    installedPaths.nginxLogsDirectory,
                ],
                staleGuestRunDocuments: [
                    installedPaths.vmIPFile,
                    installedPaths.runtimeState,
                    installedPaths.bootstrapResult,
                    installedPaths.updateActivationResult,
                    installedPaths.updateShutdownResult,
                    installedPaths.datastoreRepairResult,
                ],
                vitalFilesDirectory: { settings in
                    URL(fileURLWithPath: settings.vitalFilesDirectory)
                }
            ),
            operations: RuntimeInstallDirectoryPreparationOperations(
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                pathState: { url in
                    fileStore.pathState(at: url)
                },
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                }
            )
        )
    }

    func runtimeGuestConfigWriter() -> RuntimeGuestConfigWriter {
        RuntimeGuestConfigWriter(
            installedPaths: installedPaths,
            fileStore: fileStore,
            restrictSecretFile: restrictSecretFile
        )
    }

    func configureDeployEnvironment(_ settings: RuntimeInstallSettings) throws {
        try runtimeGuestConfigWriter().write(runtimeConfig: guestRuntimeConfigDocument(settings))
    }

    func guestRuntimeConfigDocument(_ settings: RuntimeInstallSettings) throws -> GuestRuntimeConfigDocument {
        guard let adminPassword = settings.adminPassword else {
            throw LauncherError.missingArgument("install settings adminPassword is required")
        }
        return GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            vitalServerURL: settings.vitalServerURL,
            remoteConsoleURL: settings.remoteConsoleURL,
            publicHost: settings.publicHost,
            publicPort: settings.publicPort,
            adminPassword: adminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort,
            testkitEnabled: Constants.testkitContainerIncluded
        )
    }

    func prepareInstalledExecutables() throws {
        try RuntimeInstallExecutablePreparer(
            context: RuntimeInstallExecutablePreparationContext(
                executablePaths: [
                    Constants.InstallPaths.vmBin,
                    Constants.InstallPaths.proxyRun,
                    installedPaths.nginxExecutable.path,
                ],
                chmodExecutable: Constants.Commands.chmod
            ),
            operations: RuntimeInstallExecutablePreparationOperations(
                runRequired: runRequired
            )
        ).prepare()
    }

    func provisionVMDisk(_ settings: RuntimeInstallSettings) throws {
        try RuntimeInstallVMDiskProvisioner(
            context: RuntimeInstallVMDiskProvisioningContext(
                rootfsBase: rootfsBase,
                vmDisk: vmDisk,
                runtimeDataDisk: installedPaths.runtimeDataDisk,
                gunzipExecutable: Constants.Commands.gunzip,
                truncateExecutable: Constants.Commands.truncate,
                freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes
            ),
            operations: RuntimeInstallVMDiskProvisioningOperations(
                fileState: { url in
                    fileStore.fileState(at: url)
                },
                fileSize: { url in
                    try fileStore.fileSize(url)
                },
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation
                    )
                },
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                },
                runProcessToFile: runProcessToFile,
                moveItem: { source, destination in
                    try fileStore.moveItem(at: source, to: destination)
                },
                runRequired: runRequired,
                log: log
            )
        ).provision(
            diskGiB: settings.diskGiB,
            runtimeDataDiskGiB: Constants.Defaults.defaultRuntimeDataDiskGiB
        )
    }

    func configureInstalledVMRuntime(_ settings: RuntimeInstallSettings) throws {
        try RuntimeInstallVMRuntimeConfigurator<VMRuntimeConfig>(
            context: RuntimeInstallVMRuntimeConfigurationContext(
                configURL: paths.config,
                requiredDirectories: [
                    installedPaths.runtimeDirectory,
                    installedPaths.vitalFilesDirectory,
                    installedPaths.vrReleaseDirectory,
                    installedPaths.hostRunDirectory,
                ]
            ),
            operations: RuntimeInstallVMRuntimeConfigurationOperations(
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                configPathState: { url in
                    fileStore.pathState(at: url)
                },
                loadConfig: { url in
                    try VMRuntimeConfigComposition.load(from: url, fileStore: fileStore)
                },
                defaultConfig: {
                    VMRuntimeConfig.default(paths: installedPaths)
                },
                ensureRuntimeDefaults: { config in
                    VMRuntimeConfigComposition.ensureRuntimeDefaults(&config, paths: installedPaths)
                },
                encodeConfig: { config in
                    try VMRuntimeConfigComposition.prettyJSONEncoder().encode(config)
                },
                writeData: { data, url, options in
                    try fileStore.writeData(data, to: url, options: options)
                }
            )
        ).configure(input: RuntimeInstallVMRuntimeConfigurationInput(
            cpuCount: settings.cpuCount,
            memoryGiB: settings.memoryGiB,
            networkMode: settings.networkMode,
            sharedNetworkMode: .shared,
            dataDirectoryPath: installedPaths.dataDirectory.path,
            sharedDirectoryTag: Constants.Defaults.sharedDirectoryTag,
            sharedDirectoryGuestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
            vitalFilesDirectoryPath: settings.vitalFilesDirectory,
            vitalFilesDirectoryTag: Constants.Defaults.vitalFilesDirectoryTag,
            vitalFilesDirectoryGuestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            preventSystemSleep: settings.preventSystemSleep,
            sshAuthorizedKeys: settings.sshAuthorizedKeys
        ))
    }

    func createCloudInitSeed(_ settings: RuntimeInstallSettings) throws {
        try runtimeCloudInitSeedWriter().create(
            hostname: settings.vmHostname,
            sshAuthorizedKeys: settings.sshAuthorizedKeys
        )
    }

    func configureInstalledPermissions(_ settings: RuntimeInstallSettings) throws {
        try RuntimeInstallPermissionConfigurator(
            context: RuntimeInstallPermissionContext(
                runtimeHome: paths.home,
                nginxDirectory: productRoot.appendingPathComponent("nginx"),
                proxyLaunchDaemonPlist: RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
                serviceLaunchDaemonPlists: [
                    RuntimeManagedServicePaths.launchDaemonPlist(.vm),
                    RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
                    RuntimeManagedServicePaths.launchDaemonPlist(.guestLogSync),
                    RuntimeManagedServicePaths.launchDaemonPlist(.sleepPrevention),
                    RuntimeManagedServicePaths.launchDaemonPlist(.watchdog),
                    installedPaths.automaticBackupLaunchDaemon.path,
                ],
                chownExecutable: Constants.Commands.chown,
                chmodExecutable: Constants.Commands.chmod,
                plistBuddyExecutable: Constants.Commands.plistBuddy
            ),
            operations: RuntimeInstallPermissionOperations(
                runRequired: runRequired
            )
        ).configure(input: RuntimeInstallPermissionInput(
            proxyPort: settings.proxyPort
        ))
        try setAutomaticBackupSchedule(
            enabled: RuntimeSettingsInitialBackupDefaults.automaticBackupEnabled,
            scheduleTimes: RuntimeSettingsInitialBackupDefaults.backupScheduleTimes
        )
    }

    func startInstalledServices(_ settings: RuntimeInstallSettings) throws {
        try RuntimeInstallServiceStarter(
            operations: RuntimeInstallServiceStartOperations(
                startLaunchdService: startLaunchdService,
                cleanupHostProxyPortBeforeStart: cleanupHostProxyPortBeforeStart,
                log: log
            )
        ).start(input: RuntimeInstallServiceStartInput(
            startAfterInstall: settings.startAfterInstall,
            preventSystemSleep: settings.preventSystemSleep
        ))
    }

    func applyStartOnBootPolicy(_ settings: RuntimeInstallSettings) throws {
        let plan = ApplyRuntimeInstallStartOnBootPolicyUseCase().plan(input: RuntimeInstallStartOnBootPolicyInput(
            startOnBoot: settings.startOnBoot,
            preventSystemSleep: settings.preventSystemSleep
        ))
        try RuntimeInstallStartOnBootPlanApplier(
            context: RuntimeInstallStartOnBootPlanContext(
                launchctlExecutable: Constants.Commands.launchctl
            ),
            operations: RuntimeInstallStartOnBootPlanOperations(
                setStartOnBoot: setStartOnBoot,
                runRequired: runRequired
            )
        ).apply(plan: plan)
    }

    func cleanupInstallSettings() throws {
        try RuntimeInstallSettingsCleaner(
            context: RuntimeInstallSettingsCleanupContext(
                settingsFile: URL(fileURLWithPath: Constants.InstallPaths.settingsPath)
            ),
            operations: RuntimeInstallSettingsCleanupOperations(
                pathState: { url in
                    fileStore.pathState(at: url)
                },
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                }
            )
        ).cleanup()
    }

    func runtimeServiceRestartPolicy(_ settings: RuntimeInstallSettings) -> RuntimeServiceRestartPolicy {
        RuntimeServiceRestartPolicy(
            restartVM: settings.startAfterInstall,
            restartGuestLogSync: settings.startAfterInstall,
            restartProxy: settings.startAfterInstall,
            restartWatchdog: settings.startAfterInstall
        )
    }
}
