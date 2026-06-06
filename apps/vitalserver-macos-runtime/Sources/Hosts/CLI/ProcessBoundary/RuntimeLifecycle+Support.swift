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
    func latestBackup() -> URL? {
        do {
            return try backupStore().latestBackup()
        } catch {
            log("failed to read latest backup error=\(error.localizedDescription)")
            return nil
        }
    }

    func backupStore() -> RuntimeBackupStore {
        RuntimeBackupStoreComposition.make(
            context: RuntimeBackupStoreCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeBackupStoreCompositionOperations(
                fileStore: fileStore,
                timestamp: backupTimestamp,
                isoTimestamp: isoTimestamp,
                chmodExecutable: chmodRuntimeBackupExecutable,
                log: log
            )
        )
    }

    func chmodRuntimeBackupExecutable(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0755", url.path])
    }

    func buildCloudInitSeedImage(_ request: RuntimeCloudInitSeedImageBuildRequest) throws {
        try runRequired(
            Constants.Commands.hdiutil,
            arguments: [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                request.volumeName,
                "-o",
                request.outputImage.path,
                request.sourceDirectory.path,
            ]
        )
    }

    func runtimeVersionStore() -> RuntimeVersionStore {
        RuntimeVersionStoreComposition.make(
            context: RuntimeVersionStoreCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeVersionStoreCompositionOperations(
                fileStore: fileStore,
                timestamp: isoTimestamp
            )
        )
    }

    func writeRuntimeVersion(version: String, bundle: URL) throws {
        try runtimeVersionStore().writeAppliedVersion(version: version, bundle: bundle)
    }

    func isLaunchdLoaded(_ service: RuntimeManagedService) -> Bool {
        healthChecker.isLaunchdLoaded(service)
    }

    func stopRuntimeServices() throws {
        try serviceController.stopRuntimeServices()
    }

    func stopRuntimeServicesForVMDiskReplacement() throws {
        do {
            try stopRuntimeServices()
            return
        } catch {
            log("graceful runtime services stop failed before VM disk replacement; forcing VM process stop error=\(error.localizedDescription)")
        }

        try ProcessState.forceKillAndWait(
            pidFile: paths.pidFile,
            fileStore: fileStore,
            timeoutSeconds: Constants.Runtime.vmStopWaitTimeoutSeconds,
            pollIntervalSeconds: Constants.Runtime.serviceStopPollIntervalSeconds,
            log: log
        )
        serviceController.unloadRuntimeServicesAfterForcedVMStop()
        log("runtime services stopped for VM disk replacement")
    }

    func runningVMProcessID() throws -> pid_t {
        try ProcessState.runningPid(pidFile: paths.pidFile, fileStore: fileStore)
    }

    func stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: pid_t) throws {
        try serviceController.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: expectedVMProcessID)
    }

    func startRuntimeServices(
        restartVM: Bool,
        restartGuestLogSync: Bool,
        restartProxy: Bool,
        restartWatchdog: Bool
    ) throws {
        if restartVM, preventSystemSleepEnabled() {
            try startLaunchdService(.sleepPrevention)
        }
        try serviceController.startRuntimeServices(
            restartVM: restartVM,
            restartGuestLogSync: restartGuestLogSync,
            restartProxy: false,
            restartWatchdog: false
        )
        if restartProxy {
            try cleanupHostProxyPortBeforeStart()
            try serviceController.startRuntimeServices(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: true,
                restartWatchdog: false
            )
        }
        try serviceController.startRuntimeServices(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: restartWatchdog
        )
    }

    func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        try startRuntimeServices(
            restartVM: policy.restartVM,
            restartGuestLogSync: policy.restartGuestLogSync,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    func startLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceController.startLaunchdService(service)
    }

    func restartOrStartLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceController.restartOrStartLaunchdService(service)
    }

    func restartVMRuntimeServices() throws {
        try serviceController.restartVMRuntimeServices()
    }

    func stopLaunchdService(_ service: RuntimeManagedService) {
        serviceController.stopLaunchdService(service)
    }

    func launchDaemonPlist(_ service: RuntimeManagedService) -> String {
        service.launchDaemonPlist
    }

    func waitForHealth(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        try runtimeHealthWaitRunner().wait(for: RuntimeServiceRestartPolicy(
            restartVM: restartVM,
            restartGuestLogSync: restartVM,
            restartProxy: restartProxy,
            restartWatchdog: restartWatchdog
        ))
    }

    func waitForHealth(_ policy: RuntimeServiceRestartPolicy) throws {
        try runtimeHealthWaitRunner().wait(for: policy)
    }

    func cleanupHostProxyPortBeforeStart() throws {
        try RuntimeHostProxyPortCleaner(
            proxyPort: healthChecker.installedProxyPort,
            proxyServiceLoaded: {
                isLaunchdLoaded(.proxy)
            },
            expectedProxyNginxPID: {
                healthChecker.readInstalledProxyNginxPID()
            },
            ownedNginxPathFragments: [
                installedPaths.nginxExecutable.path,
                installedPaths.nginxDirectory.path,
                "vitalserver-nginx.conf",
            ],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: runProcess,
            log: log
        ).cleanupBeforeStartingProxy()
    }

    func cleanupHostProxyPortAfterStop() throws {
        try RuntimeHostProxyPortCleaner(
            proxyPort: healthChecker.installedProxyPort,
            proxyServiceLoaded: {
                isLaunchdLoaded(.proxy)
            },
            expectedProxyNginxPID: {
                healthChecker.readInstalledProxyNginxPID()
            },
            ownedNginxPathFragments: [
                installedPaths.nginxExecutable.path,
                installedPaths.nginxDirectory.path,
                "vitalserver-nginx.conf",
            ],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: runProcess,
            log: log
        ).cleanupOwnedListenersAfterProxyStop()
    }

    func runtimeHealthWaitRunner() -> RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunnerComposition.make(
            operations: RuntimeHealthWaitRunnerCompositionOperations(
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                healthSnapshot: runtimeHealthSnapshot,
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                log: log
            )
        )
    }

    func runtimeUninstallRunner() throws -> RuntimeUninstallRunner {
        RuntimeUninstallComposition.make(
            context: RuntimeUninstallCompositionContext(
                installedPaths: installedPaths,
                pidFile: paths.pidFile
            ),
            operations: RuntimeUninstallCompositionOperations(
                fileStore: fileStore,
                configuredExternalVitalFilesDirectory: configuredExternalVitalFilesDirectory,
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                createRedisBackup: createRedisBackup,
                disableRuntimeServicesForUninstall: {
                    try serviceController.disableRuntimeServicesForUninstall()
                },
                stopRuntimeServices: stopRuntimeServices,
                cleanupHostProxyPortAfterStop: cleanupHostProxyPortAfterStop,
                packageReceiptStates: runtimePackageReceiptStates,
                openFilesInDirectory: openFilesInDirectory,
                forgetPackageReceipt: forgetPackageReceipt,
                now: { clock.now },
                log: log
            )
        )
    }

    func runtimeFreshInstallPreflight() -> RuntimeFreshInstallPreflightDocument {
        FreshInstallPreflightUseCase().run(operations: runtimeFreshInstallPreflightOperations())
    }

    func runtimeFreshInstallPreflightOperations() -> FreshInstallPreflightOperations {
        RuntimeFreshInstallPreflightComposition.make(
            context: RuntimeFreshInstallPreflightCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeFreshInstallPreflightCompositionOperations(
                fileStore: fileStore,
                serviceState: { service in
                    healthChecker.launchdState(service)
                },
                packageReceiptStates: runtimePackageReceiptStates,
                proxyPortState: { port in
                    RuntimeHostProxyPortStateReader.state(
                        port: port,
                        lsofPath: Constants.Commands.lsof,
                        runProcess: { executable, arguments in
                            runProcess(executable, arguments: arguments)
                        }
                    )
                }
            )
        )
    }

    func runtimePackageReceiptStates() -> [RuntimePackageReceiptState] {
        RuntimePackageReceiptStateReader.states(
            identifiers: Constants.Product.packageReceiptIdentifiers,
            runProcess: { executable, arguments in
                runProcess(executable, arguments: arguments)
            }
        )
    }

    func openFilesInDirectory(_ target: URL) -> RuntimeProcessResult {
        runProcess(Constants.Commands.lsof, arguments: ["+D", target.path])
    }

    func forgetPackageReceipt(_ identifier: String) -> RuntimeProcessResult {
        runProcess(Constants.Commands.pkgutil, arguments: ["--forget", identifier])
    }

    func freshInstallArtifactPaths() -> [URL] {
        RuntimeFreshInstallPreflightComposition.freshInstallArtifactPaths(installedPaths: installedPaths)
    }

    func installProvisionPayloadPaths() -> [URL] {
        freshInstallArtifactPaths()
    }

    func rotateRuntimeLogs() throws {
        try RuntimeLogRotator(
            logsDirectory: logsDirectory,
            fileStore: fileStore,
            configuration: RuntimeLogRotationConfiguration(
                fileNames: [
                    "launcher.log",
                    "launchd.out.log",
                    "launchd.err.log",
                    "proxy.out.log",
                    "proxy.err.log",
                    "proxy-nginx.access.log",
                    "proxy-nginx.error.log",
                    "guest-log-sync.out.log",
                    "guest-log-sync.err.log",
                    "sleep-prevention.out.log",
                    "sleep-prevention.err.log",
                    "watchdog.out.log",
                    "watchdog.err.log",
                ],
                maxBytes: Constants.Runtime.logRotationMaxBytes,
                keepCount: Constants.Runtime.logRotationKeepCount
            ),
            log: log
        ).rotate()
    }

    func executeBundleMaterializationCleanupPlan(_ plan: RuntimeBundleMaterializationCleanupPlan) {
        switch plan {
        case .none:
            return
        case .cleanupTemporaryRoot(let temporaryRoot):
            removeMaterializedBundleTemporaryRoot(temporaryRoot)
        }
    }

    func removeMaterializedBundleTemporaryRoot(_ temporaryRoot: URL) {
        do {
            try fileStore.removeItem(at: temporaryRoot)
        } catch {
            log(
                "bundle temporary directory cleanup failed path=\(temporaryRoot.path) error=\(RuntimeErrorDescription.describe(error))"
            )
        }
    }

    func runtimeInstallDirectoryPreparer() -> RuntimeInstallDirectoryPreparer<RuntimeInstallSettings> {
        RuntimeInstallDirectoryPreparer(
            context: RuntimeInstallDirectoryPreparationContext(
                fixedDirectories: [
                    installedPaths.runtimeDirectory,
                    installedPaths.deployDirectory,
                    installedPaths.guestRunDirectory,
                    installedPaths.vrReleaseDirectory,
                    installedPaths.backupsDirectory,
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
                fileExists: { url in
                    fileStore.fileExists(url)
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
            redisBackupRetentionCount: Constants.Defaults.redisBackupRetentionCount,
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
                gunzipExecutable: Constants.Commands.gunzip,
                truncateExecutable: Constants.Commands.truncate,
                freeSpaceMarginBytes: Constants.Runtime.freeSpaceMarginBytes
            ),
            operations: RuntimeInstallVMDiskProvisioningOperations(
                fileExists: fileExists,
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
        ).provision(diskGiB: settings.diskGiB)
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
                fileExists: fileExists,
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
        try RuntimeInstallStartOnBootPolicyApplier(
            context: RuntimeInstallStartOnBootPolicyContext(
                launchctlExecutable: Constants.Commands.launchctl
            ),
            operations: RuntimeInstallStartOnBootPolicyOperations(
                setStartOnBoot: setStartOnBoot,
                runRequired: runRequired
            )
        ).apply(input: RuntimeInstallStartOnBootPolicyInput(
            startOnBoot: settings.startOnBoot,
            preventSystemSleep: settings.preventSystemSleep
        ))
    }

    func cleanupInstallSettings() throws {
        try RuntimeInstallSettingsCleaner(
            context: RuntimeInstallSettingsCleanupContext(
                settingsFile: URL(fileURLWithPath: Constants.InstallPaths.settingsPath)
            ),
            operations: RuntimeInstallSettingsCleanupOperations(
                fileExists: fileExists,
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

    func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    func materializeRuntimeUpdateBundle(_ bundleURL: URL) throws -> RuntimeMaterializedBundle {
        try RuntimeBundleMaterializer(
            context: RuntimeBundleMaterializationContext(
                tarExecutable: Constants.Commands.tar
            ),
            operations: RuntimeBundleMaterializationOperations(
                directoryExists: directoryExists,
                fileExists: fileExists,
                temporaryRoot: {
                    fileStore.temporaryDirectory
                        .appendingPathComponent("tirosh-update-bundle-\(UUID().uuidString)", isDirectory: true)
                },
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                runProcess: runProcess,
                runRequired: runRequired,
                missingFileError: { url in
                    LauncherError.missingFile(url.path)
                },
                invalidArchiveError: { url in
                    LauncherError.bundleVerificationFailed("invalid update bundle archive: \(url.path)")
                },
                archiveValidationError: { error in
                    LauncherError.bundleVerificationFailed(error.description)
                },
                log: log
            )
        ).materialize(bundleURL)
    }

    func stageRuntimeUpdateBundle(_ input: RuntimeBundleStagingInput) throws -> URL {
        try RuntimeBundleStager(
            context: RuntimeBundleStagingContext(
                bundlesDirectory: bundlesDirectory,
                updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
            ),
            operations: RuntimeBundleStagingOperations(
                directorySize: directorySize,
                compressedSourceSize: compressedBundleSize,
                fileExists: fileExists,
                directoryExists: directoryExists,
                createDirectory: { url, withIntermediateDirectories in
                    try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
                },
                removeItem: { url in
                    try fileStore.removeItem(at: url)
                },
                copyItem: { source, destination in
                    try fileStore.copyItem(at: source, to: destination)
                },
                requireFreeSpace: { url, minimumBytes, operation in
                    try storageMaintenance().requireFreeSpace(
                        at: url,
                        minimumBytes: minimumBytes,
                        operation: operation.rawValue
                    )
                },
                log: log
            )
        ).stage(input: input)
    }

    private func compressedBundleSize(_ url: URL) throws -> UInt64 {
        fileExists(url) ? try fileSize(url) : 0
    }

    private func directorySize(_ url: URL) throws -> UInt64 {
        try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    func replaceRuntimeUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        try runtimeArtifactReplacer().replace(artifacts, stagedBundle: stagedBundle)
    }

    func runRuntimeUpdateMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        try RuntimeMigrationRunner(
            isExecutableFile: { path in fileStore.isExecutableFile(atPath: path) },
            runRequired: runRequired,
            log: log
        ).run(migrations, stagedBundle: stagedBundle)
    }

    func validateRuntimeUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        try runtimeArtifactReplacer().validatePayload(artifact, source: source)
    }

    private func runtimeArtifactReplacer() -> RuntimeArtifactReplacer {
        RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            rules: RuntimeArtifactReplacementRules(
                tarCommand: Constants.Commands.tar,
                appBundleRoot: Constants.Product.managerAppName,
                nginxBundleRoot: "nginx",
                guestDeployRoot: "deploy",
                runtimeToolsAllowedRootEntries: [
                    "vitalserver-vm",
                    "vitalserver-proxy-run",
                    URL(fileURLWithPath: Constants.InstallPaths.uninstall).lastPathComponent,
                ]
            ),
            temporaryDirectory: fileStore.temporaryDirectory,
            fileExists: fileExists,
            directoryExists: directoryExists,
            fileSize: fileSize,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            removeItem: { url in try fileStore.removeItem(at: url) },
            moveItem: { source, destination in try fileStore.moveItem(at: source, to: destination) },
            readUTF8Text: { url in try fileStore.readUTF8Text(url) },
            runRequired: runRequired,
            runProcessToFile: runProcessToFile,
            log: log
        )
    }

    func resizeVMDiskIfNeeded(diskGiB: Int) throws {
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(vmDisk.path)
        }
        let bytesPerGiB: UInt64 = 1024 * 1024 * 1024
        let currentGiB = Int((try fileSize(vmDisk) + bytesPerGiB - 1) / bytesPerGiB)
        guard diskGiB >= currentGiB else {
            throw LauncherError.missingArgument(
                "--disk-gib can only increase the VM disk; current disk is \(currentGiB) GiB"
            )
        }
        guard diskGiB > currentGiB else {
            return
        }
        try runRequired(Constants.Commands.truncate, arguments: ["-s", "\(diskGiB)G", vmDisk.path])
        log("resized vm disk path=\(vmDisk.path) from=\(currentGiB) GiB to=\(diskGiB) GiB")
    }

    func createReplacementVMDisk(_ plan: RepairRuntimeVMDiskReplacementBuildPlan) throws {
        try runProcessToFile(
            Constants.Commands.gunzip,
            arguments: ["-c", plan.rootfsBase.path],
            output: plan.temporaryDisk
        )
        try runRequired(
            Constants.Commands.truncate,
            arguments: ["-s", "\(plan.targetDiskGiB)G", plan.temporaryDisk.path]
        )
    }

    func storageMaintenance() -> RuntimeStorageMaintenance {
        RuntimeStorageMaintenance(
            fileStore: fileStore,
            configuration: RuntimeStorageMaintenanceConfiguration(
                backupKeepCount: Constants.Runtime.backupKeepCount,
                stagedBundleKeepCount: Constants.Runtime.stagedBundleKeepCount
            ),
            log: log
        )
    }

    func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now)
    }

    func log(_ message: String) {
        print("[\(isoTimestamp())] \(message)")
    }

    func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: clock.now)
    }

    func runtimeVersionValue() -> String {
        switch runtimeVersionStore().readVersion() {
        case .loaded(let version):
            return version
        case .missing:
            log("runtime version unavailable reason=missing")
            return RuntimeVersionStore.missingVersionValue
        case .failed(let reason):
            log("runtime version unavailable reason=invalid error=\(reason)")
            return RuntimeVersionStore.invalidVersionValue
        }
    }

    func runtimeStatusValue() -> String? {
        statusReporter.statusValue()
    }

    func runtimeObservedEventPublisher() -> RuntimeObservedEventPublisher {
        RuntimeObservedEventPublisher(
            previousStatus: {
                statusReporter.loadStatus()?.status
            },
            recordEvent: { status, previousStatus, operation, message, snapshot, eventType in
                try runtimeEventPublisher().recordObservedEvent(
                    status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    healthSnapshot: snapshot,
                    eventType: eventType
                )
            },
            recordEventBestEffort: { status, previousStatus, operation, message, snapshot, eventType in
                runtimeEventPublisher().recordObservedEventBestEffort(
                    status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    healthSnapshot: snapshot,
                    eventType: eventType
                )
            }
        )
    }

    func runtimeEventPublisher() -> RuntimeEventPublisher {
        RuntimeEventPublisher(
            factory: runtimeEventFactory(),
            recorder: runtimeObservationRecorder()
        )
    }

    func runtimeObservationRecorder() -> RuntimeObservationRecorder {
        RuntimeObservationRecorder(
            eventRepository: CompositeRuntimeEventRepository(
                primary: JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents),
                secondary: SQLiteRuntimeEventRepository(url: installedPaths.runtimeObservabilityDB),
                log: log
            ),
            log: log
        )
    }

    func runtimeEventFactory() -> RuntimeEventFactory {
        RuntimeEventFactory(
            timestamp: isoTimestamp,
            product: Constants.Product.identifier,
            runtimeVersion: runtimeVersionValue
        )
    }

    func vitalDBObservationProjector() -> RuntimeVitalDBObservationProjector {
        RuntimeVitalDBObservationProjector(
            appendObservation: { observation in
                try SQLiteVitalDBObservationRepository(url: installedPaths.runtimeObservabilityDB).append(observation)
            },
            log: log
        )
    }

    func projectVitalDBObservationBestEffort(_ observation: VitalDBObservationDocument) {
        vitalDBObservationProjector().projectBestEffort(observation)
    }

    func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        healthChecker.snapshot()
    }

    func runtimeStatusWriter() -> RuntimeStatusWriter {
        RuntimeStatusWriterComposition.make(
            operations: RuntimeStatusWriterCompositionOperations(
                reporter: statusReporter,
                timestamp: isoTimestamp,
                runtimeVersion: runtimeVersionValue,
                healthSnapshot: runtimeHealthSnapshot,
                latestBackup: latestBackup
            )
        )
    }

    func runtimeObservedStatusPublisher() -> RuntimeObservedStatusPublisher {
        RuntimeObservedStatusPublisher(
            writeStatus: { status, operation, message, progress in
                try runtimeStatusWriter().writeStatus(
                    status,
                    operation: operation,
                    message: message,
                    progress: progress
                )
            },
            projectObservation: { observation in
                projectVitalDBObservationBestEffort(observation)
            }
        )
    }

    func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try runtimeObservedStatusPublisher().publishStatus(
            status,
            operation: operation,
            message: message,
            progress: progress
        )
    }

    func writeRuntimeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        let progress = RuntimeProgressDocument(
            operation: operation,
            phase: phase,
            step: step,
            stepStatus: stepStatus,
            message: message,
            reasonCodes: reasonCodes,
            startedAt: nil,
            updatedAt: isoTimestamp()
        )
        do {
            try runtimeStatusWriter().writeProgress(
                status,
                operation: operation,
                step: step,
                stepStatus: stepStatus,
                phase: phase,
                message: message,
                reasonCodes: reasonCodes
            )
        } catch {
            runtimeEventPublisher().recordProgressEventBestEffort(
                status: status,
                message: message,
                progress: progress
            )
            throw error
        }
        runtimeEventPublisher().recordProgressEventBestEffort(
            status: status,
            message: message,
            progress: progress
        )
    }

    func setInstalledProxyPort(_ port: Int) throws {
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(port)",
                launchDaemonPlist(.proxy),
            ]
        )
    }

    func readSecretFile(_ url: URL) throws -> String {
        guard url.path.hasPrefix("/private/tmp/") || url.path.hasPrefix("/tmp/") else {
            throw LauncherError.missingArgument("--admin-password-file must be under /private/tmp")
        }
        let data = try fileStore.readData(url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw LauncherError.missingArgument("--admin-password-file must be UTF-8")
        }
        return value
    }

    func restrictSecretFile(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0600", url.path])
    }

    func setStartOnBoot(_ enabled: Bool) throws {
        try serviceController.setStartOnBoot(enabled)
    }

    func setSystemSleepPrevention(_ enabled: Bool) throws {
        let plist = URL(fileURLWithPath: RuntimeManagedService.sleepPrevention.launchDaemonPlist)
        guard fileExists(plist) else {
            log("system sleep prevention service is not installed; setting recorded only")
            return
        }
        let action = enabled ? "enable" : "disable"
        try runRequired(Constants.Commands.launchctl, arguments: [
            action,
            "system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
        if enabled {
            try startLaunchdService(.sleepPrevention)
        } else {
            stopLaunchdService(.sleepPrevention)
        }
        log("system sleep prevention \(enabled ? "enabled" : "disabled")")
    }

    func preventSystemSleepEnabled() -> Bool {
        runtimeConfigFlagReader().preventSystemSleepEnabled()
    }

    func runtimeConfigFlagReader() -> RuntimeConfigFlagReader {
        RuntimeConfigFlagReader(
            loadFlags: {
                let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
                return RuntimeConfigFlagValues(
                    autoRecoveryEnabled: config.autoRecoveryEnabled,
                    preventSystemSleep: config.preventSystemSleep
                )
            },
            log: log
        )
    }

    func configuredExternalVitalFilesDirectory() -> RuntimeConfiguredExternalVitalFilesDirectoryRead {
        do {
            let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
            if let hostPath = config.vitalFilesDirectory?.hostPath, hostPath.hasPrefix("/") {
                let url = URL(fileURLWithPath: hostPath)
                guard url.path != installedPaths.vitalFilesDirectory.path else {
                    return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
                }
                return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: url, failure: nil)
            }
            return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
        } catch {
            let reason = error.localizedDescription
            log("failed to read configured vital files directory error=\(reason)")
            return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: reason)
        }
    }

    func runtimeCommandExecutor() -> RuntimeCommandExecutor {
        RuntimeCommandExecutor(
            commandRunner: commandRunner,
            log: log,
            recordCommandEvent: { eventType, executable, arguments, result in
                runtimeEventPublisher().recordCommandEventBestEffort(
                    eventType,
                    executable: executable,
                    arguments: arguments,
                    result: result
                )
            }
        )
    }

    func runProcess(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        runtimeCommandExecutor().run(executable, arguments)
    }

    func runRequired(_ executable: String, arguments: [String]) throws {
        try runtimeCommandExecutor().runRequired(executable, arguments)
    }

    func runProcessToFile(_ executable: String, arguments: [String], output: URL) throws {
        try runtimeCommandExecutor().runWritingOutput(executable, arguments, output: output)
    }

    func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }
}
