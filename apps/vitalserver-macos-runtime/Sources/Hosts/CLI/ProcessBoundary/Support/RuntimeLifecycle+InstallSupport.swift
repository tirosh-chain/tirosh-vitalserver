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
                    installedPaths.runtimeObservation,
                    installedPaths.bootstrapResult,
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

    func initializeHostStateStore() throws {
        let migrationResult = try SQLiteRuntimeOperationLeaseLegacyMigrator(
            databaseURL: installedPaths.runtimeStateDatabase,
            sourceURL: installedPaths.runtimeOperationLease,
            fileStore: fileStore
        ).migrate()
        let database = SQLiteHostRuntimeStateDatabase(
            url: installedPaths.runtimeStateDatabase,
            fileStore: fileStore
        )
        switch database.loadHostStateStoreReadiness() {
        case .loaded(let metadata):
            log(
                "Host runtime state store ready schemaVersion=\(metadata.schemaVersion) databaseId=\(metadata.databaseID) leaseMigration=\(migrationResult)"
            )
        case .missing:
            throw RuntimeHostStateStoreStartupError.missing(
                path: installedPaths.runtimeStateDatabase.path
            )
        case .failed(let failure):
            throw RuntimeHostStateStoreStartupError.failed(
                path: installedPaths.runtimeStateDatabase.path,
                stage: failure.stage.rawValue,
                reason: failure.message
            )
        }
    }

    func prepareHostSettings(_ settings: RuntimeInstallSettings) throws {
        let repository = runtimeHostSettingsRepository()
        switch repository.loadHostSettings() {
        case .missing:
            break
        case .loaded(let record):
            log("Host settings already initialized; preserving revision=\(record.revision)")
            return
        case .failed(let reason):
            throw RuntimeHostStateStoreStartupError.failed(
                path: installedPaths.runtimeStateDatabase.path,
                stage: "host-settings-read",
                reason: reason
            )
        }
        let record = try repository.initializeDesiredHostSettings(
            try freshInstallHostSettingsPayload(settings),
            desiredAt: ISO8601DateFormatter().string(from: clock.now)
        )
        log("Host settings initialized revision=\(record.revision)")
    }

    func migrateLegacyHostSettingsIfNeeded() throws {
        let repository = runtimeHostSettingsRepository()
        switch repository.loadHostSettings() {
        case .loaded(let record):
            log("Host settings migration not required revision=\(record.revision)")
            return
        case .failed(let reason):
            throw LauncherError.runtimeOperationFailed(reason)
        case .missing:
            break
        }

        let urls = [paths.config, installedPaths.guestRuntimeConfig, installedPaths.guestRuntimeSettings]
        let states = urls.map { fileStore.pathState(at: $0) }
        if states.allSatisfy({ $0 == .missing }) {
            log("Legacy Host settings migration not required; materialized settings are absent")
            return
        }
        guard states.allSatisfy({ $0 == .file }) else {
            let evidence = zip(urls, states)
                .map { "\($0.0.path)=\($0.1.rawValue)" }
                .joined(separator: ",")
            throw LauncherError.runtimeOperationFailed(
                "Legacy Host settings migration blocked by incomplete materialized state: \(evidence)"
            )
        }

        let payload = RuntimeHostSettingsPayload(
            vmConfigJSON: try fileStore.readData(paths.config),
            guestRuntimeConfigJSON: try fileStore.readData(installedPaths.guestRuntimeConfig),
            guestRuntimeSettingsJSON: try fileStore.readData(installedPaths.guestRuntimeSettings)
        )
        _ = try JSONDecoder().decode(VMRuntimeConfig.self, from: payload.vmConfigJSON)
        _ = try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: payload.guestRuntimeConfigJSON)
        _ = try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: payload.guestRuntimeSettingsJSON)
        let imported = try repository.importMaterializedHostSettings(
            payload,
            importedAt: ISO8601DateFormatter().string(from: clock.now)
        )
        log("Legacy materialized Host settings imported revision=\(imported.revision)")
    }

    func loadPackageProvisionSettings() throws -> RuntimeInstallSettings {
        switch runtimeHostSettingsRepository().loadHostSettings() {
        case .missing:
            return try RuntimeInstallSettings.load(
                defaultVitalFilesDirectory: installedPaths.vitalFilesDirectory.path,
                fileStore: fileStore
            )
        case .failed(let reason):
            throw LauncherError.runtimeOperationFailed(reason)
        case .loaded(let record):
            return try packageProvisionSettings(from: record)
        }
    }

    func requirePackageReinstallSettings() throws -> RuntimeInstallSettings {
        switch runtimeHostSettingsRepository().loadHostSettings() {
        case .loaded(let record):
            return try packageProvisionSettings(from: record)
        case .missing:
            throw LauncherError.runtimeOperationFailed(
                "Package reinstall Host settings are missing after legacy migration"
            )
        case .failed(let reason):
            throw LauncherError.runtimeOperationFailed(reason)
        }
    }

    func writePackageInstallContract(
        mode: RuntimePackageInstallMode,
        to url: URL
    ) throws {
        let contract = RuntimePackageInstallContract(
            packageIdentifier: Constants.Product.identifier,
            mode: mode
        )
        try fileStore.writeData(
            try JSONEncoder.pretty.encode(contract),
            to: url,
            options: .atomic
        )
        log("package install contract written path=\(url.path) mode=\(mode.rawValue)")
    }

    func loadPackageInstallContract(from url: URL) throws -> RuntimePackageInstallContract {
        let contract: RuntimePackageInstallContract
        do {
            contract = try JSONDecoder().decode(
                RuntimePackageInstallContract.self,
                from: fileStore.readData(url)
            )
        } catch {
            throw LauncherError.runtimeOperationFailed(
                "Package install contract read failed path=\(url.path) reason=\(RuntimeErrorDescription.describe(error))"
            )
        }
        guard contract.schemaVersion == RuntimePackageInstallContract.currentSchemaVersion else {
            throw LauncherError.runtimeOperationFailed(
                "Package install contract schema is unsupported path=\(url.path) schemaVersion=\(contract.schemaVersion)"
            )
        }
        guard contract.packageIdentifier == Constants.Product.identifier else {
            throw LauncherError.runtimeOperationFailed(
                "Package install contract identifier mismatch path=\(url.path) actual=\(contract.packageIdentifier) expected=\(Constants.Product.identifier)"
            )
        }
        return contract
    }

    private func packageProvisionSettings(
        from record: RuntimeHostSettingsRecord
    ) throws -> RuntimeInstallSettings {
        let vmConfig = try JSONDecoder().decode(VMRuntimeConfig.self, from: record.payload.vmConfigJSON)
        let guestConfig = try JSONDecoder().decode(
            GuestRuntimeConfigDocument.self,
            from: record.payload.guestRuntimeConfigJSON
        )
        let gibibyte = UInt64(1_073_741_824)
        guard vmConfig.memoryMiB % 1024 == 0 else {
            throw LauncherError.runtimeOperationFailed(
                "Persisted VM memory is not an integral GiB value memoryMiB=\(vmConfig.memoryMiB)"
            )
        }
        let diskBytes = try fileStore.fileSize(vmDisk)
        guard diskBytes % gibibyte == 0 else {
            throw LauncherError.runtimeOperationFailed(
                "Existing VM disk size is not an integral GiB value path=\(vmDisk.path) bytes=\(diskBytes)"
            )
        }
        guard let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath else {
            throw LauncherError.runtimeOperationFailed("Persisted Vital files directory is missing")
        }

        var settings = RuntimeInstallSettings(vitalFilesDirectory: vitalFilesDirectory)
        settings.cpuCount = vmConfig.cpuCount
        settings.memoryGiB = Int(vmConfig.memoryMiB / 1024)
        settings.diskGiB = Int(diskBytes / gibibyte)
        settings.networkMode = vmConfig.network.mode
        settings.proxyPort = guestConfig.publicPort
        settings.adminPassword = guestConfig.adminPassword
        settings.vmHostname = Constants.Guest.hostname
        settings.sshAuthorizedKeys = vmConfig.sshAuthorizedKeys ?? []
        settings.vitalServerURL = guestConfig.vitalServerURL
        settings.remoteConsoleURL = guestConfig.remoteConsoleURL
        settings.publicHost = guestConfig.publicHost
        settings.publicPort = guestConfig.publicPort
        settings.startOnBoot = try persistedStartOnBootState()
        settings.startAfterInstall = settings.startOnBoot
        settings.preventSystemSleep = vmConfig.preventSystemSleep ?? false
        log(
            "Loaded package provision settings from Host settings revision=\(record.revision) diskGiB=\(settings.diskGiB) startOnBoot=\(settings.startOnBoot)"
        )
        return settings
    }

    private func persistedStartOnBootState() throws -> Bool {
        let result = runProcess(Constants.Commands.launchctl, arguments: ["print-disabled", "system"])
        guard result.exitCode == 0 else {
            let reason = result.stderr.isEmpty ? "launchctl print-disabled failed" : result.stderr
            throw LauncherError.runtimeOperationFailed(reason)
        }
        for service in RuntimeManagedService.startOrder where result.stdout.contains("\"\(service.label)\" => true") {
            return false
        }
        return true
    }

    func configureDeployEnvironment(_ settings: RuntimeInstallSettings) throws {
        let record = try requiredInstallHostSettings()
        _ = try JSONDecoder().decode(
            GuestRuntimeConfigDocument.self,
            from: record.payload.guestRuntimeConfigJSON
        )
        _ = try JSONDecoder().decode(
            GuestRuntimeSettingsDocument.self,
            from: record.payload.guestRuntimeSettingsJSON
        )
        try fileStore.writeData(
            record.payload.guestRuntimeConfigJSON,
            to: installedPaths.guestRuntimeConfig,
            options: .atomic
        )
        try fileStore.writeData(
            record.payload.guestRuntimeSettingsJSON,
            to: installedPaths.guestRuntimeSettings,
            options: .atomic
        )
        try restrictSecretFile(installedPaths.guestRuntimeConfig)
        try prepareRuntimeControlSettings()
    }

    func prepareRuntimeControlSettings() throws {
        let url = installedPaths.runtimeControlSettings
        switch fileStore.pathState(at: url) {
        case .file:
            do {
                _ = try JSONDecoder().decode(
                    RuntimeControlSettingsDocument.self,
                    from: fileStore.readData(url)
                )
            } catch {
                throw LauncherError.runtimeOperationFailed(
                    "Runtime Control settings validation failed path=\(url.path) reason=\(RuntimeErrorDescription.describe(error))"
                )
            }
            log("Preserved existing Runtime Control settings path=\(url.path)")
        case .missing:
            try fileStore.writeData(
                try VMRuntimeConfigComposition.prettyJSONEncoder().encode(
                    RuntimeControlSettingsDocument()
                ),
                to: url,
                options: .atomic
            )
            log("Runtime Control settings initialized path=\(url.path)")
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "Runtime Control settings inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "Runtime Control settings path state is unexpected path=\(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }
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
            swaggerUiPort: Constants.Guest.swaggerUIPort
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
        let record = try requiredInstallHostSettings()
        _ = try JSONDecoder().decode(VMRuntimeConfig.self, from: record.payload.vmConfigJSON)
        for directory in [
            installedPaths.runtimeDirectory,
            installedPaths.vitalFilesDirectory,
            installedPaths.vrReleaseDirectory,
            installedPaths.hostRunDirectory,
        ] {
            try fileStore.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try fileStore.writeData(record.payload.vmConfigJSON, to: paths.config, options: .atomic)
        let materialized = RuntimeHostSettingsPayload(
            vmConfigJSON: try fileStore.readData(paths.config),
            guestRuntimeConfigJSON: try fileStore.readData(installedPaths.guestRuntimeConfig),
            guestRuntimeSettingsJSON: try fileStore.readData(installedPaths.guestRuntimeSettings)
        )
        guard materialized == record.payload else {
            throw LauncherError.runtimeOperationFailed(
                "Host settings materialization verification failed revision=\(record.revision)"
            )
        }
        _ = try runtimeHostSettingsRepository().markHostSettingsMaterialized(
            revision: record.revision,
            materializedAt: ISO8601DateFormatter().string(from: clock.now)
        )
    }

    func freshInstallHostSettingsPayload(
        _ settings: RuntimeInstallSettings
    ) throws -> RuntimeHostSettingsPayload {
        let configurator = RuntimeInstallVMRuntimeConfigurator<VMRuntimeConfig>(
            context: RuntimeInstallVMRuntimeConfigurationContext(
                configURL: paths.config,
                requiredDirectories: []
            ),
            operations: RuntimeInstallVMRuntimeConfigurationOperations(
                createDirectory: { _, _ in },
                configPathState: { _ in .missing },
                loadConfig: { _ in
                    throw LauncherError.runtimeOperationFailed(
                        "fresh install must not read materialized VM config"
                    )
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
                writeData: { _, _, _ in }
            )
        )
        let input = RuntimeInstallVMRuntimeConfigurationInput(
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
        )
        let vmConfig = configurator.configuredFromDefault(input: input)
        let guestConfig = try guestRuntimeConfigDocument(settings)
        let guestSettings = GuestRuntimeSettingsDocument(runtimeConfig: guestConfig)
        let encoder = VMRuntimeConfigComposition.prettyJSONEncoder()
        return RuntimeHostSettingsPayload(
            vmConfigJSON: try encoder.encode(vmConfig),
            guestRuntimeConfigJSON: try encoder.encode(guestConfig),
            guestRuntimeSettingsJSON: try encoder.encode(guestSettings)
        )
    }

    func runtimeHostSettingsRepository() -> SQLiteRuntimeHostSettingsRepository {
        SQLiteRuntimeHostSettingsRepository(
            databaseURL: installedPaths.runtimeStateDatabase,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
    }

    func requiredInstallHostSettings() throws -> RuntimeHostSettingsRecord {
        switch runtimeHostSettingsRepository().loadHostSettings() {
        case .loaded(let record):
            return record
        case .missing:
            throw LauncherError.runtimeOperationFailed("Host settings SQLite state is missing")
        case .failed(let reason):
            throw LauncherError.runtimeOperationFailed(reason)
        }
    }

    func createCloudInitSeed(_ settings: RuntimeInstallSettings) throws {
        log("Refreshing cloud-init seed so package deploy bootstrap is activated")
        try runtimeCloudInitSeedWriter().create(
            hostname: settings.vmHostname,
            sshAuthorizedKeys: settings.sshAuthorizedKeys
        )
    }

    func configureInstalledPermissions(_ settings: RuntimeInstallSettings) throws {
        let record = try requiredInstallHostSettings()
        let guestConfig = try JSONDecoder().decode(
            GuestRuntimeConfigDocument.self,
            from: record.payload.guestRuntimeConfigJSON
        )
        let guestSettings = try JSONDecoder().decode(
            GuestRuntimeSettingsDocument.self,
            from: record.payload.guestRuntimeSettingsJSON
        )
        try RuntimeInstallPermissionConfigurator(
            context: RuntimeInstallPermissionContext(
                runtimeHome: paths.home,
                nginxDirectory: productRoot.appendingPathComponent("nginx"),
                runtimeStateDatabase: installedPaths.runtimeStateDatabase,
                runtimeControlSettings: installedPaths.runtimeControlSettings,
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
            proxyPort: guestConfig.publicPort
        ))
        try setAutomaticBackupSchedule(
            enabled: guestSettings.automaticBackupEnabled,
            scheduleTimes: guestSettings.backupScheduleTimes
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
