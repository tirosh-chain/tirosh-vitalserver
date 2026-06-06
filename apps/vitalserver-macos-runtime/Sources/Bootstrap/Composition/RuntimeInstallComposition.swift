import Application
import Foundation
import OutboundAdapters
import Contracts
import Domain
import InboundAdapters
import Workflow
import Errors

private typealias InstallSettings = RuntimeInstallSettings

public struct RuntimeInstallCompositionContext {
    let paths: LauncherPaths
    let installedPaths: InstalledRuntimePaths
    let productRoot: URL
    let rootfsBase: URL
    let vmDisk: URL

    public init(
        paths: LauncherPaths,
        installedPaths: InstalledRuntimePaths,
        productRoot: URL,
        rootfsBase: URL,
        vmDisk: URL
    ) {
        self.paths = paths
        self.installedPaths = installedPaths
        self.productRoot = productRoot
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
    }
}

public struct RuntimeInstallCompositionOperations {
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

    public init(
        fileStore: RuntimeFileStore,
        now: @escaping () -> Date,
        freshInstallPreflight: @escaping () -> RuntimeFreshInstallPreflightDocument,
        installProvisionPayload: @escaping () -> RuntimeInstallProvisionPayloadDocument,
        writeRuntimeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeRuntimeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        rotateRuntimeLogs: @escaping () throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, String) throws -> Void,
        runRequired: @escaping (String, [String]) throws -> Void,
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        writeInstalledRuntimeVersion: @escaping () throws -> Void,
        setStartOnBoot: @escaping (Bool) throws -> Void,
        startLaunchdService: @escaping (RuntimeManagedService) throws -> Void,
        cleanupHostProxyPortBeforeStart: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        restrictSecretFile: @escaping (URL) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.fileStore = fileStore
        self.now = now
        self.freshInstallPreflight = freshInstallPreflight
        self.installProvisionPayload = installProvisionPayload
        self.writeRuntimeStatus = writeRuntimeStatus
        self.writeRuntimeProgress = writeRuntimeProgress
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.requireFreeSpace = requireFreeSpace
        self.runRequired = runRequired
        self.runProcessToFile = runProcessToFile
        self.writeInstalledRuntimeVersion = writeInstalledRuntimeVersion
        self.setStartOnBoot = setStartOnBoot
        self.startLaunchdService = startLaunchdService
        self.cleanupHostProxyPortBeforeStart = cleanupHostProxyPortBeforeStart
        self.waitForHealth = waitForHealth
        self.restrictSecretFile = restrictSecretFile
        self.log = log
    }
}

public struct RuntimeInstallComposition {
    let context: RuntimeInstallCompositionContext
    let operations: RuntimeInstallCompositionOperations

    public init(
        context: RuntimeInstallCompositionContext,
        operations: RuntimeInstallCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func install() throws {
        let plan = installRuntimeUseCase().plan(for: InstallRuntimeRequest(
            mode: .full
        ))
        try runtimeInstallComposition().run(plan)
    }

    public func installProvision() throws {
        let plan = installRuntimeUseCase().plan(for: InstallRuntimeRequest(
            mode: .provision
        ))
        try runtimeInstallComposition().run(plan)
    }

    private func installRuntimeUseCase() -> InstallRuntimeUseCase {
        InstallRuntimeUseCase()
    }

    private func runtimeInstallComposition() -> RuntimeInstallWorkflow<InstallSettings> {
        RuntimeInstallWorkflow(
            readers: RuntimeInstallStateReaders(
                loadSettings: {
                    try loadInstallSettings()
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

    private func loadInstallSettings() throws -> InstallSettings {
        do {
            return try RuntimeInstallSettings.load(
                path: Constants.InstallPaths.settingsPath,
                defaultVitalFilesDirectory: context.installedPaths.vitalFilesDirectory.path,
                fileStore: operations.fileStore,
                defaults: installSettingsDefaults()
            )
        } catch RuntimeInstallSettingsError.missingArgument(let message) {
            throw LauncherError.missingArgument(message)
        }
    }

    private func installSettingsDefaults() -> RuntimeInstallSettingsDefaults {
        RuntimeInstallSettingsDefaults(
            cpuCount: 8,
            memoryGiB: Constants.Defaults.defaultMemoryGiB,
            diskGiB: Constants.Defaults.defaultDiskGiB,
            networkMode: .shared,
            proxyPort: Constants.Guest.publicPort,
            adminPassword: Constants.Guest.defaultAdminPassword,
            vmHostname: Constants.Guest.hostname,
            publicPort: Constants.Guest.publicPort,
            minimumCPUCount: Constants.Defaults.minimumCPUCount,
            maximumAllowedCPUCount: Constants.Defaults.maximumAllowedCPUCount,
            minimumMemoryGiB: Constants.Defaults.minimumMemoryGiB,
            maximumAllowedMemoryGiB: Constants.Defaults.maximumAllowedMemoryGiB,
            memoryStepGiB: Constants.Defaults.memoryStepGiB,
            minimumDiskGiB: Constants.Defaults.minimumDiskGiB,
            maximumDiskGiB: Constants.Defaults.maximumDiskGiB,
            diskStepGiB: Constants.Defaults.diskStepGiB
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
        try runtimeGuestConfigWriter().write(runtimeConfig: guestRuntimeConfigDocument(settings))
    }

    private func guestRuntimeConfigDocument(_ settings: InstallSettings) throws -> GuestRuntimeConfigDocument {
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
            redisBackupRetentionCount: Constants.Defaults.redisBackupRetentionCount,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort,
            testkitEnabled: Constants.testkitContainerIncluded
        )
    }

    private func prepareInstalledExecutables() throws {
        try RuntimeInstallExecutablePreparer(
            context: RuntimeInstallExecutablePreparationContext(
                executablePaths: [
                    Constants.InstallPaths.vmBin,
                    Constants.InstallPaths.proxyRun,
                    context.installedPaths.nginxExecutable.path,
                ],
                chmodExecutable: Constants.Commands.chmod
            ),
            operations: RuntimeInstallExecutablePreparationOperations(
                runRequired: operations.runRequired
            )
        ).prepare()
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
                    try VMRuntimeConfigComposition.load(from: url, fileStore: operations.fileStore)
                },
                defaultConfig: {
                    VMRuntimeConfigComposition.defaultConfig(paths: context.installedPaths)
                },
                ensureRuntimeDefaults: { config in
                    VMRuntimeConfigComposition.ensureRuntimeDefaults(&config, paths: context.installedPaths)
                },
                encodeConfig: { config in
                    try VMRuntimeConfigComposition.prettyJSONEncoder().encode(config)
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
            preventSystemSleep: settings.preventSystemSleep,
            sshAuthorizedKeys: settings.sshAuthorizedKeys
        ))
    }

    private func createCloudInitSeed(_ settings: InstallSettings) throws {
        try RuntimeCloudInitSeedComposition.make(
            runtimeDirectory: context.installedPaths.runtimeDirectory,
            fileStore: operations.fileStore,
            runRequired: operations.runRequired
        ).create(hostname: settings.vmHostname, sshAuthorizedKeys: settings.sshAuthorizedKeys)
    }

    private func configureInstalledPermissions(_ settings: InstallSettings) throws {
        try RuntimeInstallPermissionConfigurator(
            context: RuntimeInstallPermissionContext(
                runtimeHome: context.paths.home,
                nginxDirectory: context.productRoot.appendingPathComponent("nginx"),
                proxyLaunchDaemonPlist: RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
                serviceLaunchDaemonPlists: [
                    RuntimeManagedServicePaths.launchDaemonPlist(.vm),
                    RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
                    RuntimeManagedServicePaths.launchDaemonPlist(.guestLogSync),
                    RuntimeManagedServicePaths.launchDaemonPlist(.sleepPrevention),
                    RuntimeManagedServicePaths.launchDaemonPlist(.watchdog),
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
                settingsFile: URL(fileURLWithPath: Constants.InstallPaths.settingsPath)
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

}
