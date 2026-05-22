import CryptoKit
import Foundation
import RuntimeCore
import HostRuntimeInfrastructure

struct RuntimeLifecycle {
    let paths: LauncherPaths
    private let installedPaths: InstalledRuntimePaths
    private let clock: RuntimeClock
    private let sleeper: RuntimeSleeper
    private let commandRunner: RuntimeCommandRunner
    private let httpProber: RuntimeHTTPProber
    private let serviceManager: RuntimeServiceManager
    private let statusReporter: RuntimeStatusReporter
    private let healthChecker: RuntimeHealthChecker
    private let serviceController: RuntimeServiceController
    private let guestGateway: RuntimeGuestGateway
    private let fileStore: RuntimeFileStore

    init(
        paths: LauncherPaths,
        clock: RuntimeClock = SystemRuntimeClock(),
        sleeper: RuntimeSleeper = ThreadRuntimeSleeper(),
        commandRunner: RuntimeCommandRunner = SystemRuntimeCommandRunner(),
        httpProber: RuntimeHTTPProber? = nil,
        serviceManager: RuntimeServiceManager? = nil,
        runtimeStatusRepository: RuntimeStatusRepository? = nil,
        guestGateway: RuntimeGuestGateway? = nil,
        fileStore: RuntimeFileStore = LocalRuntimeFileStore()
    ) {
        self.paths = paths
        self.installedPaths = paths.installed
        self.clock = clock
        self.sleeper = sleeper
        self.commandRunner = commandRunner
        let resolvedHTTPProber = httpProber ?? CurlRuntimeHTTPProber(commandRunner: commandRunner)
        let resolvedServiceManager = serviceManager ?? LaunchdRuntimeServiceManager(commandRunner: commandRunner)
        self.httpProber = resolvedHTTPProber
        self.serviceManager = resolvedServiceManager
        self.fileStore = fileStore
        self.statusReporter = RuntimeStatusReporter(
            repository: runtimeStatusRepository ?? JSONFileRuntimeStatusRepository(url: installedPaths.runtimeStatus),
            productRoot: installedPaths.productRoot,
            runtimeHome: installedPaths.runtimeHome
        )
        let guestRunDirectory = installedPaths.guestRunDirectory
        let resolvedGuestGateway = guestGateway ?? JSONFileRuntimeGuestGateway(
            runtimeStateURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.runtimeStateFile),
            bootstrapResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.bootstrapResultFile),
            updateActivationRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateActivationRequestFile),
            updateActivationResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.updateActivationResultFile),
            datastoreRepairRequestURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairRequestFile),
            datastoreRepairResultURL: guestRunDirectory.appendingPathComponent(Constants.Runtime.datastoreRepairResultFile)
        )
        self.guestGateway = resolvedGuestGateway
        let resolvedHealthChecker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: resolvedServiceManager,
            commandRunner: commandRunner,
            httpProber: resolvedHTTPProber,
            guestGateway: resolvedGuestGateway
        )
        self.healthChecker = resolvedHealthChecker
        self.serviceController = RuntimeServiceController(
            serviceManager: resolvedServiceManager,
            isLoaded: { label in
                resolvedHealthChecker.isLaunchdLoaded(label)
            },
            log: { message in
                print("[\(ISO8601DateFormatter().string(from: clock.now))] \(message)")
            }
        )
    }

    private var productRoot: URL {
        installedPaths.productRoot
    }

    private var bundlesDirectory: URL {
        installedPaths.bundlesDirectory
    }

    private var backupsDirectory: URL {
        installedPaths.backupsDirectory
    }

    private var statusDirectory: URL {
        installedPaths.statusDirectory
    }

    private var logsDirectory: URL {
        installedPaths.centralRuntimeLogsDirectory
    }

    private var runtimeStatus: URL {
        installedPaths.runtimeStatus
    }

    private var rootfsBase: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    private var vmDisk: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
    }

    private var runtimeVersion: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion)
    }

    private var vmIPFile: URL {
        installedPaths.vmIPFile
    }

    private var guestRunDirectory: URL {
        installedPaths.guestRunDirectory
    }

    private var guestBootstrapLog: URL {
        installedPaths.bootstrapLog
    }

    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "install":
            try install()
        case "status":
            printStatus()
        case "health":
            try health()
        case "watchdog":
            try watchdog()
        case "configure":
            try configure(arguments: Array(arguments.dropFirst()))
        case "verify-bundle":
            guard let bundlePath = arguments.dropFirst().first else {
                throw LauncherError.missingArgument("usage: vitalserver-vm runtime verify-bundle <bundle.tar.gz>")
            }
            try verifyBundle(URL(fileURLWithPath: bundlePath))
        case "stage-bundle":
            guard let bundlePath = arguments.dropFirst().first else {
                throw LauncherError.missingArgument("usage: vitalserver-vm runtime stage-bundle <bundle.tar.gz>")
            }
            _ = try stageBundle(URL(fileURLWithPath: bundlePath))
        case "apply-bundle":
            guard let bundlePath = arguments.dropFirst().first else {
                throw LauncherError.missingArgument("usage: vitalserver-vm runtime apply-bundle <bundle.tar.gz>")
            }
            try applyBundle(URL(fileURLWithPath: bundlePath))
        case "rollback":
            let backupPath = arguments.dropFirst().first
            try rollback(backupPath.map { URL(fileURLWithPath: $0) })
        case "repair-datastore":
            try repairDatastore()
        case "start-services":
            try startServices()
        case "stop-services":
            try stopServices()
        case "-h", "--help", "help":
            printUsage()
        default:
            throw LauncherError.unsupportedCommand("runtime \(command)")
        }
    }

    func printUsage() {
        print(
            """
            Usage:
              vitalserver-vm runtime install
              vitalserver-vm runtime status
              vitalserver-vm runtime health
              vitalserver-vm runtime watchdog
              vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--disk-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--vital-files-dir <path>] [--public-host <host>] [--public-port <port>] [--admin-password <password>] [--start-on-boot true|false] [--restart]
              vitalserver-vm runtime configure [--admin-password-file <path>] [--restart]
              vitalserver-vm runtime verify-bundle <bundle.tar.gz>
              vitalserver-vm runtime stage-bundle <bundle.tar.gz>
              vitalserver-vm runtime apply-bundle <bundle.tar.gz>
              vitalserver-vm runtime rollback [backup-dir]
              vitalserver-vm runtime repair-datastore
              vitalserver-vm runtime start-services
              vitalserver-vm runtime stop-services
            """
        )
    }

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
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            writeProgress: { event in
                try writeRuntimeProgress(
                    event.status,
                    operation: event.operation,
                    step: event.step,
                    stepStatus: event.stepStatus,
                    phase: event.phase,
                    message: event.message
                )
            },
            runtimeHomePath: { paths.home.path },
            log: log
        )
    }

    private func runtimeInstallStepExecutor() -> RuntimeInstallStepExecutor {
        RuntimeInstallStepExecutor(
            prepareInstallDirectories: { settings in
                try runtimeInstallDirectoryPreparer().prepare(settings: settings)
            },
            rotateRuntimeLogs: {
                try rotateRuntimeLogs()
            },
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
            writeInstalledRuntimeVersion: {
                try writeInstalledRuntimeVersion()
            },
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
            now: { clock.now }
        )
    }

    private func runtimeGuestConfigWriter() -> RuntimeGuestConfigWriter {
        RuntimeGuestConfigWriter(
            installedPaths: installedPaths,
            fileStore: fileStore,
            restrictSecretFile: { url in
                try restrictSecretFile(url)
            }
        )
    }

    func printStatus() {
        print("Tirosh VitalServer runtime")
        print("  product root: \(productRoot.path)")
        print("  runtime dir: \(installedPaths.runtimeDirectory.path)")
        print("  latest backup: \(latestBackup()?.path ?? "none")")
        print("  status file: \(fileState(url: runtimeStatus))")
        print("  status: \(runtimeStatusValue())")
        print("  launcher: \(fileState(path: Constants.InstallPaths.vmBin))")
        print("  proxy runner: \(fileState(path: Constants.InstallPaths.proxyRun))")
        print("  rootfs base: \(fileState(url: rootfsBase))")
        print("  vm disk: \(fileState(url: vmDisk))")
        print("  version: \(runtimeVersionValue())")
        print("  VM service: \(launchdState(Constants.Launchd.vmService))")
        print("  proxy service: \(launchdState(Constants.Launchd.proxyService))")
        print("  watchdog service: \(launchdState(Constants.Launchd.watchdogService))")
        print("  VM IP: \(guestRuntimeState()?.vmIP ?? readTrimmed(vmIPFile) ?? "waiting")")
        let proxyPort = installedProxyPort()
        print("  proxy port: \(proxyPort)")
        print("  host proxy HTTP: \(httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: proxyPort)))")
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
            try runRequired(Constants.Commands.chmod, arguments: ["0755", path])
        }
    }

    private func provisionVMDisk(_ settings: InstallSettings) throws {
        if !fileExists(vmDisk), fileExists(rootfsBase) {
            try requireFreeSpace(
                at: vmDisk.deletingLastPathComponent(),
                minimumBytes: (try fileSize(rootfsBase) * 6) + Constants.Runtime.freeSpaceMarginBytes,
                operation: "provision-vm-disk"
            )
            let temporary = vmDisk.deletingLastPathComponent().appendingPathComponent(".\(vmDisk.lastPathComponent).tmp")
            if fileExists(temporary) {
                try fileStore.removeItem(at: temporary)
            }
            try runProcessToFile(
                Constants.Commands.gunzip,
                arguments: ["-c", rootfsBase.path],
                output: temporary
            )
            try fileStore.moveItem(at: temporary, to: vmDisk)
            log("created vm disk path=\(vmDisk.path) source=\(rootfsBase.lastPathComponent)")
        }
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(rootfsBase.path)
        }
        try runRequired(Constants.Commands.truncate, arguments: ["-s", "\(settings.diskGiB)G", vmDisk.path])
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
        try createCloudInitSeed(hostname: settings.vmHostname)
    }

    private func createCloudInitSeed(hostname: String) throws {
        let seedDir = installedPaths.runtimeDirectory.appendingPathComponent("cloud-init-seed")
        let seedISO = installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.cloudInit)
        if directoryExists(seedDir) {
            try fileStore.removeItem(at: seedDir)
        }
        try fileStore.createDirectory(at: seedDir, withIntermediateDirectories: true)
        let instanceID = "tirosh-\(UUID().uuidString.lowercased())"
        try fileStore.writeData(Data("""
        instance-id: \(instanceID)
        local-hostname: \(hostname)

        """.utf8), to: seedDir.appendingPathComponent("meta-data"), options: .atomic)

        try fileStore.writeData(Data("""
        #cloud-config
        hostname: \(hostname)
        manage_etc_hosts: true
        ssh_pwauth: true
        disable_root: true
        users:
          - default
          - name: ubuntu
            groups: [adm, sudo]
            shell: /bin/bash
            sudo: ALL=(ALL) NOPASSWD:ALL
            lock_passwd: false
            ssh_authorized_keys: []
        chpasswd:
          expire: false
          users:
            - name: ubuntu
              password: ubuntu
              type: text
        runcmd:
          - mkdir -p /mnt/tirosh
          - mountpoint -q /mnt/tirosh || mount -t virtiofs tirosh /mnt/tirosh
          - mkdir -p /mnt/tirosh/run
          - test -x /mnt/tirosh/deploy/bootstrap.sh
          - bash -lc '/mnt/tirosh/deploy/bootstrap.sh > /mnt/tirosh/run/bootstrap.log 2>&1'

        """.utf8), to: seedDir.appendingPathComponent("user-data"), options: .atomic)

        if fileExists(seedISO) {
            try fileStore.removeItem(at: seedISO)
        }
        try runRequired(
            Constants.Commands.hdiutil,
            arguments: [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                "cidata",
                "-o",
                seedISO.path,
                seedDir.path,
            ]
        )
    }

    private func writeInstalledRuntimeVersion() throws {
        try runtimeVersionStore().writeInstalledVersion(version: Constants.launcherVersion)
    }

    private func configureInstalledPermissions(_ settings: InstallSettings) throws {
        try runRequired(Constants.Commands.chown, arguments: ["-R", "root:wheel", paths.home.path])
        try runRequired(Constants.Commands.chown, arguments: ["-R", "root:wheel", "\(productRoot.path)/nginx"])
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
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
            try runRequired(Constants.Commands.chmod, arguments: ["0644", plist])
            try runRequired(Constants.Commands.chown, arguments: ["root:wheel", plist])
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

    func health() throws {
        printStatus()
        let snapshot = runtimeHealthSnapshot()
        let failed = !snapshot.isHealthy

        if failed {
            try? writeRuntimeStatus(
                .degraded,
                operation: .health,
                message: "runtime health check failed: \(reasonText(snapshot.failureReasons))"
            )
            print("health: failed")
            throw LauncherError.runtimeHealthFailed
        }
        try writeRuntimeStatus(.healthy, operation: .health, message: "runtime health check passed")
        print("health: ok")
    }

    func watchdog() throws {
        try runtimeWatchdogRunner().run()
    }

    private func automaticRecoveryEnabled() -> Bool {
        guard let config = try? VMRuntimeConfig.load(from: paths.config, fileStore: fileStore) else {
            return true
        }
        return config.autoRecoveryEnabled ?? true
    }

    private func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: statusReporter,
            now: { clock.now },
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            log: log
        )
    }

    private func runtimeWatchdogRunner() -> RuntimeWatchdogRunner {
        RuntimeWatchdogRunner(
            actions: RuntimeWatchdogActions(
                prepareLogs: {
                    try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    try? rotateRuntimeLogs()
                },
                activeManagedOperation: {
                    runtimeManagedOperationGuard().activeOperation()
                },
                healthSnapshot: {
                    runtimeHealthSnapshot()
                },
                proxyLivenessHTTP: { port in
                    httpProber.statusCode(url: Constants.Runtime.proxyLivenessURL(port: port))
                },
                automaticRecoveryEnabled: {
                    automaticRecoveryEnabled()
                },
                restartService: { label in
                    restartLaunchdService(label)
                },
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                writeStatus: { status, operation, message in
                    try writeRuntimeStatus(status, operation: operation, message: message)
                }
            ),
            log: log
        )
    }

    private func runtimeConfigureRunner() -> RuntimeConfigureRunner {
        RuntimeConfigureRunner(
            installedPaths: installedPaths,
            configURL: paths.config,
            fileStore: fileStore,
            actions: RuntimeConfigureActions(
                resizeVMDiskIfNeeded: { diskGiB in
                    try resizeVMDiskIfNeeded(diskGiB: diskGiB)
                },
                setInstalledProxyPort: { port in
                    try setInstalledProxyPort(port)
                },
                readSecretFile: { url in
                    try readSecretFile(url)
                },
                restrictSecretFile: { url in
                    try restrictSecretFile(url)
                },
                setStartOnBoot: { enabled in
                    try setStartOnBoot(enabled)
                },
                restartRuntimeServices: {
                    restartLaunchdService(Constants.Launchd.vmService)
                    restartLaunchdService(Constants.Launchd.proxyService)
                    restartLaunchdService(Constants.Launchd.watchdogService)
                }
            ),
            log: { message in
                log(message)
            }
        )
    }

    func configure(arguments: [String]) throws {
        let result = try runtimeConfigureRunner().configure(arguments: arguments)
        try writeRuntimeStatus(.degraded, operation: .configure, message: "runtime configuration updated")

        guard result.restart else {
            print("runtime configuration updated; restart required for VM/guest changes")
            return
        }
        print("runtime configuration updated and services restarted")
    }

    func verifyBundle(_ bundleURL: URL) throws {
        log("bundle verification started path=\(bundleURL.path)")
        let materialized = try materializeBundleInput(bundleURL)
        defer { materialized.cleanup?() }
        try verifyBundleDirectory(materialized.bundleURL, sourceURL: bundleURL)
    }

    private func verifyBundleDirectory(_ bundleURL: URL, sourceURL: URL) throws {
        let manifestURL = bundleURL.appendingPathComponent(Constants.Bundle.manifest)
        let checksumsURL = bundleURL.appendingPathComponent(Constants.Bundle.checksums)
        let signatureURL = bundleURL.appendingPathComponent(Constants.Bundle.signature)

        guard directoryExists(bundleURL) else {
            throw LauncherError.missingFile(bundleURL.path)
        }
        for url in [manifestURL, checksumsURL, signatureURL] {
            guard fileExists(url) else {
                throw LauncherError.missingFile(url.path)
            }
        }

        let manifest = try loadManifest(manifestURL)
        let plan = try makeBundleVerificationPlan(manifest)
        log(
            "bundle manifest loaded version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)"
        )

        let checksumMap = try loadChecksums(checksumsURL)
        for (artifact, fileVerification) in zip(manifest.artifacts, plan.artifactFiles) {
            let artifactURL = bundleURL.appendingPathComponent(fileVerification.name)
            guard fileExists(artifactURL) else {
                throw LauncherError.missingFile(artifactURL.path)
            }

            log(
                "verifying artifact type=\(artifact.type.rawValue) name=\(artifact.name) size=\(formatBytes(bundleItemSize(artifact.size)))"
            )
            try verifyDigestedFile(
                artifactURL,
                fileVerification: fileVerification,
                checksumMap: checksumMap
            )
            try validateUpdateArtifactPayload(artifact, source: artifactURL)
        }

        for (migration, fileVerification) in zip(manifest.migrations, plan.migrationFiles) {
            let migrationURL = bundleURL.appendingPathComponent(fileVerification.checksumKey)
            guard fileExists(migrationURL) else {
                throw LauncherError.missingFile(migrationURL.path)
            }

            log("verifying migration name=\(migration.name) size=\(formatBytes(bundleItemSize(migration.size)))")
            try verifyDigestedFile(
                migrationURL,
                fileVerification: fileVerification,
                checksumMap: checksumMap
            )
        }

        log("bundle verification completed path=\(sourceURL.path)")
        print("bundle verified: \(sourceURL.path)")
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        log("bundle stage started source=\(bundleURL.path)")
        let materialized = try materializeBundleInput(bundleURL)
        defer { materialized.cleanup?() }
        try verifyBundleDirectory(materialized.bundleURL, sourceURL: bundleURL)
        let manifest = try loadManifest(materialized.bundleURL.appendingPathComponent(Constants.Bundle.manifest))
        let destination = bundlesDirectory.appendingPathComponent("update-bundle-\(manifest.version)")
        let bundleSize = try directorySize(materialized.bundleURL)

        try fileStore.createDirectory(at: bundlesDirectory, withIntermediateDirectories: true)
        if fileExists(destination) || directoryExists(destination) {
            log("removing existing staged bundle path=\(destination.path)")
            try fileStore.removeItem(at: destination)
        }
        try requireFreeSpace(
            at: bundlesDirectory,
            minimumBytes: bundleSize + compressedBundleSize(bundleURL) + Constants.Runtime.updateFreeSpaceMarginBytes,
            operation: .stageBundle
        )
        log(
            "copying bundle to managed storage source=\(materialized.bundleURL.path) destination=\(destination.path) size=\(formatBytes(bundleSize))"
        )
        try fileStore.copyItem(at: materialized.bundleURL, to: destination)
        log("bundle stage completed destination=\(destination.path)")
        print("bundle staged: \(destination.path)")
        return destination
    }

    func applyBundle(_ bundleURL: URL) throws {
        try runtimeApplyBundleRunner().run(bundleURL: bundleURL)
        log("mutable VM disk preserved path=\(vmDisk.path)")
    }

    private struct MaterializedBundleInput {
        let bundleURL: URL
        let cleanup: (() -> Void)?
    }

    private func materializeBundleInput(_ bundleURL: URL) throws -> MaterializedBundleInput {
        if directoryExists(bundleURL) {
            return MaterializedBundleInput(bundleURL: bundleURL, cleanup: nil)
        }
        guard fileExists(bundleURL), isUpdateBundleArchive(bundleURL) else {
            throw LauncherError.missingFile(bundleURL.path)
        }

        let temporaryRoot = fileStore.temporaryDirectory
            .appendingPathComponent("tirosh-update-bundle-\(UUID().uuidString)", isDirectory: true)
        try fileStore.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let extractedBundle = try extractBundleArchive(bundleURL, to: temporaryRoot)
        return MaterializedBundleInput(
            bundleURL: extractedBundle,
            cleanup: { try? fileStore.removeItem(at: temporaryRoot) }
        )
    }

    private func extractBundleArchive(_ archiveURL: URL, to temporaryRoot: URL) throws -> URL {
        let listResult = runProcess(Constants.Commands.tar, arguments: ["-tzf", archiveURL.path])
        guard listResult.exitCode == 0 else {
            let stderr = listResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                log("bundle archive list failed stderr=\(stderr)")
            }
            throw LauncherError.bundleVerificationFailed("invalid update bundle archive: \(archiveURL.path)")
        }

        let rootName = try validateBundleArchiveEntries(listResult.stdout)
        try validateBundleArchiveEntryTypes(archiveURL)
        try runRequired(Constants.Commands.tar, arguments: ["-xzf", archiveURL.path, "-C", temporaryRoot.path])
        let extractedBundle = temporaryRoot.appendingPathComponent(rootName, isDirectory: true)
        guard directoryExists(extractedBundle) else {
            throw LauncherError.missingFile(extractedBundle.path)
        }
        log("bundle archive extracted source=\(archiveURL.path) destination=\(extractedBundle.path)")
        return extractedBundle
    }

    private func validateBundleArchiveEntries(_ output: String) throws -> String {
        let entries = output.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else {
            throw LauncherError.bundleVerificationFailed("empty update bundle archive")
        }

        var rootName: String?
        for entry in entries {
            guard !entry.hasPrefix("/"), !entry.contains("\\") else {
                throw LauncherError.bundleVerificationFailed("unsafe update bundle archive path: \(entry)")
            }
            let components = entry
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty,
                  !components.contains("."),
                  !components.contains("..") else {
                throw LauncherError.bundleVerificationFailed("unsafe update bundle archive path: \(entry)")
            }
            if let existingRoot = rootName {
                guard existingRoot == components[0] else {
                    throw LauncherError.bundleVerificationFailed("update bundle archive must contain a single root directory")
                }
            } else {
                rootName = components[0]
            }
        }

        guard let rootName else {
            throw LauncherError.bundleVerificationFailed("empty update bundle archive")
        }
        return rootName
    }

    private func validateBundleArchiveEntryTypes(_ archiveURL: URL) throws {
        let result = runProcess(Constants.Commands.tar, arguments: ["-tvzf", archiveURL.path])
        guard result.exitCode == 0 else {
            throw LauncherError.bundleVerificationFailed("invalid update bundle archive: \(archiveURL.path)")
        }
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw LauncherError.bundleVerificationFailed(
                    "update bundle archive must not contain links: \(archiveURL.lastPathComponent)"
                )
            }
        }
    }

    private func isUpdateBundleArchive(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".tar.gz") || url.lastPathComponent.hasSuffix(".tgz")
    }

    private func compressedBundleSize(_ url: URL) throws -> UInt64 {
        fileExists(url) ? try fileSize(url) : 0
    }

    private func runtimeApplyBundleRunner() -> RuntimeApplyBundleRunner {
        RuntimeApplyBundleRunner(
            prepareLogs: {
                try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                try? rotateRuntimeLogs()
            },
            initialHealthSnapshot: runtimeHealthSnapshot,
            preparePreflight: prepareApplyBundlePreflight,
            executeStep: executeApplyBundleStep,
            rollback: rollback,
            startRuntimeServices: startRuntimeServices,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            writeProgress: { event in
                try writeRuntimeProgress(
                    event.status,
                    operation: event.operation,
                    step: event.step,
                    stepStatus: event.stepStatus,
                    phase: event.phase,
                    message: event.message
                )
            },
            pruneOldRuntimeArtifacts: pruneOldRuntimeArtifacts,
            reasonText: reasonText,
            log: log
        )
    }

    private func prepareApplyBundlePreflight(_ bundleURL: URL) throws -> ApplyBundlePreflightContext {
        try RuntimeApplyBundlePreflightRunner(
            stageBundle: stageBundle,
            loadManifest: loadManifest,
            fileExists: fileExists,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            fileSize: fileSize,
            requireFreeSpace: { url, minimumBytes, operation in
                try requireFreeSpace(at: url, minimumBytes: minimumBytes, operation: operation)
            },
            checkCompatibility: { manifest in
                try RuntimeUpdateCompatibilityChecker.check(
                    manifest: manifest,
                    currentUpdaterVersion: Constants.launcherVersion,
                    currentPlatform: Constants.Platform.current
                )
            },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(
                    restartVM: isLaunchdLoaded(Constants.Launchd.vmService),
                    restartProxy: isLaunchdLoaded(Constants.Launchd.proxyService),
                    restartWatchdog: isLaunchdLoaded(Constants.Launchd.watchdogService)
                )
            },
            createBackup: { reason in try backupStore().createBackup(reason: reason) },
            directorySize: directorySize,
            log: log
        ).prepare(
            bundleURL: bundleURL,
            backupsDirectory: backupsDirectory,
            rootfsBase: rootfsBase
        )
    }

    private func executeApplyBundleStep(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext
    ) throws {
        try RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: stopRuntimeServices,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            fileSize: fileSize,
            replaceFile: { source, destination in try replaceFile(from: source, to: destination) },
            replaceUpdateArtifacts: { artifacts, stagedBundle in
                try replaceUpdateArtifacts(artifacts, stagedBundle: stagedBundle)
            },
            runMigrations: { migrations, stagedBundle in
                try runMigrations(migrations, stagedBundle: stagedBundle)
            },
            refreshCloudInitSeedIfNeeded: refreshCloudInitSeedIfNeeded,
            writeRuntimeVersion: { version, bundle in try writeRuntimeVersion(version: version, bundle: bundle) },
            startRuntimeServices: startRuntimeServices,
            activateGuestUpdateIfNeeded: activateGuestUpdateIfNeeded,
            waitForHealth: waitForHealth,
            log: log
        ).execute(step, preflight: preflight, rootfsBase: rootfsBase)
    }

    func repairDatastore() throws {
        try runtimeDatastoreRepairRunner().run()
    }

    private func runtimeDatastoreRepairRunner() -> RuntimeDatastoreRepairRunner {
        RuntimeDatastoreRepairRunner(
            prepareGuestRunDirectory: {
                try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
            },
            removePreviousResult: {
                try guestGateway.removeDatastoreRepairResult()
            },
            writeRequest: { requestID, requestedAt in
                try guestGateway.writeDatastoreRepairRequest(requestId: requestID, requestedAt: requestedAt)
            },
            isVMServiceLoaded: {
                isLaunchdLoaded(Constants.Launchd.vmService)
            },
            startVMService: {
                startLaunchdService(Constants.Launchd.vmService)
            },
            restartVMService: {
                restartLaunchdService(Constants.Launchd.vmService)
            },
            waitForResult: { requestID in
                try waitForDatastoreRepairResult(requestId: requestID)
            },
            restartProxyService: {
                restartLaunchdService(Constants.Launchd.proxyService)
            },
            restartWatchdogService: {
                restartLaunchdService(Constants.Launchd.watchdogService)
            },
            waitForHealth: waitForHealth,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            makeRequestID: {
                UUID().uuidString
            },
            timestamp: isoTimestamp,
            log: log
        )
    }

    func startServices() throws {
        try runtimeServiceControlRunner().startAll()
    }

    func stopServices() throws {
        try runtimeServiceControlRunner().stopAll()
    }

    private func runtimeServiceControlRunner() -> RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: startRuntimeServices,
            stopRuntimeServices: stopRuntimeServices,
            waitForHealth: waitForHealth,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            log: log
        )
    }

    func rollback(_ requestedBackup: URL?) throws {
        try runtimeRollbackRunner().run(requestedBackup: requestedBackup)
    }

    private func runtimeRollbackRunner() -> RuntimeRollbackRunner {
        RuntimeRollbackRunner(
            preparePreflight: prepareRollbackPreflight,
            executeStep: executeRollbackStep,
            writeStatus: { status, operation, message in
                try writeRuntimeStatus(status, operation: operation, message: message)
            },
            writeProgress: { event in
                try writeRuntimeProgress(
                    event.status,
                    operation: event.operation,
                    step: event.step,
                    stepStatus: event.stepStatus,
                    phase: event.phase,
                    message: event.message
                )
            },
            vmDiskPath: { vmDisk.path },
            log: log
        )
    }

    private func prepareRollbackPreflight(_ requestedBackup: URL?) throws -> RollbackPreflightContext {
        try RuntimeRollbackPreflightRunner(
            requireLatestBackup: { try backupStore().requireLatestBackup() },
            directoryExists: directoryExists,
            fileExists: fileExists,
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(
                    restartVM: isLaunchdLoaded(Constants.Launchd.vmService),
                    restartProxy: isLaunchdLoaded(Constants.Launchd.proxyService),
                    restartWatchdog: isLaunchdLoaded(Constants.Launchd.watchdogService)
                )
            },
            log: log
        ).prepare(requestedBackup: requestedBackup)
    }

    private func executeRollbackStep(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext
    ) throws {
        let executor = RuntimeRollbackStepExecutor(
            stopRuntimeServices: stopRuntimeServices,
            replaceFile: { source, destination in try replaceFile(from: source, to: destination) },
            fileExists: fileExists,
            writeRuntimeVersion: { version, bundle in try writeRuntimeVersion(version: version, bundle: bundle) },
            restoreBackupPathIfExists: { source, destination in
                try backupStore().restoreBackupPathIfExists(source, to: destination)
            },
            restoreRuntimeToolsIfExists: { source in try backupStore().restoreRuntimeToolsIfExists(source) },
            startRuntimeServices: startRuntimeServices,
            waitForHealth: waitForHealth
        )
        try executor.execute(
            step,
            preflight: preflight,
            rootfsBase: rootfsBase,
            runtimeVersion: runtimeVersion,
            managerAppPath: URL(fileURLWithPath: Constants.Product.managerAppPath),
            nginxDirectory: installedPaths.nginxDirectory,
            deployDirectory: installedPaths.deployDirectory
        )
    }

    private func loadManifest(_ url: URL) throws -> UpdateBundleManifest {
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
    }

    private func loadChecksums(_ url: URL) throws -> [String: String] {
        let text = try fileStore.readUTF8Text(url)
        var checksums: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else {
                continue
            }
            checksums[String(parts[1]).trimmingCharacters(in: .whitespaces)] = String(parts[0])
        }
        return checksums
    }

    private func makeBundleVerificationPlan(_ manifest: UpdateBundleManifest) throws -> UpdateBundleVerificationPlan {
        do {
            return try UpdateBundleVerifier.makePlan(
                manifest: manifest,
                expectedProduct: Constants.Product.identifier
            )
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try fileStore.readData(url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyDigestedFile(
        _ url: URL,
        fileVerification: UpdateBundleFileVerification,
        checksumMap: [String: String]
    ) throws {
        log(
            "checksum started key=\(fileVerification.checksumKey) path=\(url.path) expectedSize=\(formatBytes(bundleItemSize(fileVerification.expectedSize)))"
        )
        let actualDigest = try sha256(url)
        let size = Int(try fileSize(url))
        do {
            try UpdateBundleVerifier.verifyDigest(
                checksumKey: fileVerification.checksumKey,
                expectedSHA256: fileVerification.expectedSHA256,
                expectedSize: fileVerification.expectedSize,
                checksumMap: checksumMap,
                actualSHA256: actualDigest,
                actualSize: size
            )
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
        log("checksum completed key=\(fileVerification.checksumKey) actualSize=\(formatBytes(bundleItemSize(size)))")
    }

    private func launcherError(_ error: UpdateBundleVerificationError) -> LauncherError {
        switch error {
        case .unsupportedSchema(let schemaVersion):
            return .missingArgument("unsupported bundle schema: \(schemaVersion)")
        case .unsupportedProduct(let product):
            return .missingArgument("unsupported bundle product: \(product)")
        case .invalidArtifactName(let name):
            return .missingArgument("invalid artifact name: \(name)")
        case .invalidMigrationName(let name):
            return .missingArgument("invalid migration name: \(name)")
        case .unsupportedArtifactType(let type):
            return .bundleVerificationFailed("unsupported artifact type: \(type)")
        case .manifestChecksumMismatch(let checksumKey):
            return .bundleVerificationFailed("manifest checksum mismatch for \(checksumKey)")
        case .checksumFileMismatch(let checksumKey):
            return .bundleVerificationFailed("checksums.txt mismatch for \(checksumKey)")
        case .sizeMismatch(let checksumKey):
            return .bundleVerificationFailed("size mismatch for \(checksumKey)")
        }
    }

    private func runMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        try RuntimeMigrationRunner(
            isExecutableFile: { path in fileStore.isExecutableFile(atPath: path) },
            runRequired: { path, arguments in try runRequired(path, arguments: arguments) },
            log: log
        ).run(migrations, stagedBundle: stagedBundle)
    }

    private func replaceUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        try makeArtifactReplacer().replace(artifacts, stagedBundle: stagedBundle)
    }

    private func validateUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        try makeArtifactReplacer().validatePayload(artifact, source: source)
    }

    private func makeArtifactReplacer() -> RuntimeArtifactReplacer {
        RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
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
            runRequired: { executable, arguments in try runRequired(executable, arguments: arguments) },
            runProcessToFile: { executable, arguments, output in
                try runProcessToFile(executable, arguments: arguments, output: output)
            },
            log: log
        )
    }

    private func latestBackup() -> URL? {
        backupStore().latestBackup()
    }

    private func backupStore() -> RuntimeBackupStore {
        RuntimeBackupStore(
            paths: RuntimeBackupStorePaths(
                backupsDirectory: backupsDirectory,
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            timestamp: backupTimestamp,
            isoTimestamp: isoTimestamp,
            fileExists: fileExists,
            directoryExists: directoryExists,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            copyItem: { source, destination in try fileStore.copyItem(at: source, to: destination) },
            removeItem: { url in try fileStore.removeItem(at: url) },
            writeData: { data, url in try fileStore.writeData(data, to: url, options: []) },
            contentsOfDirectory: { url in try fileStore.contentsOfDirectory(at: url, skipsHiddenFiles: false) },
            childDirectories: { url, fragment in
                try fileStore.childDirectories(at: url, nameContains: fragment, skipsHiddenFiles: true)
            },
            chmodExecutable: { url in try runRequired(Constants.Commands.chmod, arguments: ["0755", url.path]) },
            log: log
        )
    }

    private func runtimeVersionStore() -> RuntimeVersionStore {
        RuntimeVersionStore(
            versionFile: runtimeVersion,
            timestamp: isoTimestamp,
            fileExists: fileExists,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            readData: { url in try fileStore.readData(url) },
            writeData: { data, url in try fileStore.writeData(data, to: url, options: []) }
        )
    }

    private func pruneOldRuntimeArtifacts() throws {
        try pruneOldDirectories(in: backupsDirectory, keep: Constants.Runtime.backupKeepCount, requiredNameFragment: "-before-")
        try pruneOldDirectories(in: bundlesDirectory, keep: Constants.Runtime.stagedBundleKeepCount, requiredNameFragment: "update-bundle-")
    }

    private func pruneOldDirectories(in directory: URL, keep: Int, requiredNameFragment: String) throws {
        guard let matchingDirectories = try? fileStore.childDirectories(
            at: directory,
            nameContains: requiredNameFragment,
            skipsHiddenFiles: true
        ) else {
            return
        }
        let directories = matchingDirectories.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in directories.dropLast(keep) {
            try fileStore.removeItem(at: directory)
            log("pruned runtime artifact path=\(directory.path)")
        }
    }

    private func replaceFile(from source: URL, to destination: URL) throws {
        try fileStore.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp")
        log(
            "file replacement started source=\(source.path) destination=\(destination.path) temporary=\(temporary.path) size=\(formatBytes(try fileSize(source)))"
        )
        if fileExists(temporary) {
            try fileStore.removeItem(at: temporary)
        }
        try fileStore.copyItem(at: source, to: temporary)
        if fileExists(destination) {
            try fileStore.removeItem(at: destination)
        }
        try fileStore.moveItem(at: temporary, to: destination)
        log("file replacement completed destination=\(destination.path)")
    }

    private func writeRuntimeVersion(version: String, bundle: URL) throws {
        try runtimeVersionStore().writeAppliedVersion(version: version, bundle: bundle)
    }

    private func isLaunchdLoaded(_ label: String) -> Bool {
        healthChecker.isLaunchdLoaded(label)
    }

    private func stopRuntimeServices() throws {
        serviceController.stopRuntimeServices()
    }

    private func startRuntimeServices(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        serviceController.startRuntimeServices(
            restartVM: restartVM,
            restartProxy: restartProxy,
            restartWatchdog: restartWatchdog
        )
    }

    private func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        serviceController.startRuntimeServices(policy)
    }

    private func startLaunchdService(_ label: String) {
        serviceController.startLaunchdService(label)
    }

    private func restartLaunchdService(_ label: String) {
        serviceController.restartLaunchdService(label)
    }

    private func launchDaemonPlist(_ label: String) -> String {
        "\(Constants.InstallPaths.launchDaemons)/\(label).plist"
    }

    private func refreshCloudInitSeedIfNeeded(_ manifest: UpdateBundleManifest) throws {
        guard manifest.artifacts.contains(where: { $0.type == .guestDeploy }) else {
            log("cloud-init seed refresh not required")
            return
        }
        log("refreshing cloud-init seed so guest bootstrap can activate updated deploy bundle")
        try createCloudInitSeed(hostname: Constants.Guest.hostname)
    }

    private func activateGuestUpdateIfNeeded(_ manifest: UpdateBundleManifest) throws {
        try RuntimeGuestActivationRunner(
            createRunDirectory: {
                try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
            },
            removePreviousResult: {
                try guestGateway.removeUpdateActivationResult()
            },
            requestID: { UUID().uuidString },
            timestamp: isoTimestamp,
            writeRequest: { requestId, requestedAt, version in
                try guestGateway.writeUpdateActivationRequest(
                    requestId: requestId,
                    requestedAt: requestedAt,
                    version: version
                )
            },
            isVMServiceLoaded: {
                isLaunchdLoaded(Constants.Launchd.vmService)
            },
            startVMService: {
                startLaunchdService(Constants.Launchd.vmService)
            },
            loadResult: {
                guestGateway.loadUpdateActivationResult()
            },
            reportProgress: { message in
                try? writeRuntimeStatus(
                    .recovering,
                    operation: .activateGuestUpdate,
                    message: message
                )
            },
            sleep: {
                sleeper.sleep(forTimeInterval: 3)
            },
            log: log
        ).activateIfNeeded(manifest: manifest)
    }

    private func waitForHealth(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        guard restartVM || restartProxy || restartWatchdog else {
            log("runtime services were not running before apply; skipping health wait")
            return
        }

        log("waiting for runtime health timeoutSeconds=\(Constants.Runtime.waitTimeoutSeconds)")
        let maxAttempts = Int(ceil(Constants.Runtime.waitTimeoutSeconds / 3.0))
        let waitResult = RuntimeHealthWaiter.wait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: maxAttempts, progressEveryAttempts: 5),
            observe: {
                RuntimeHealthWaitObservation(
                    vmServiceRequired: restartVM,
                    proxyServiceRequired: restartProxy,
                    watchdogServiceRequired: restartWatchdog,
                    vmServiceLoaded: isLaunchdLoaded(Constants.Launchd.vmService),
                    proxyServiceLoaded: isLaunchdLoaded(Constants.Launchd.proxyService),
                    watchdogServiceLoaded: isLaunchdLoaded(Constants.Launchd.watchdogService),
                    snapshot: runtimeHealthSnapshot()
                )
            },
            onProgress: { reasons in
                let reasonText = reasonText(reasons)
                log("waiting for runtime health reasons=\(reasonText)")
                try? writeRuntimeStatus(
                    .recovering,
                    operation: .health,
                    message: "waiting for runtime health: \(reasonText)"
                )
            },
            sleep: {
                sleeper.sleep(forTimeInterval: 3)
            }
        )

        switch waitResult {
        case .healthy:
            let snapshot = runtimeHealthSnapshot()
            log("runtime health ok hostProxyHTTP=\(snapshot.hostProxyHTTP)")
        case .failedEarly(let reason):
            log("runtime health failed early reason=\(reason.rawValue)")
            throw LauncherError.runtimeHealthFailed
        case .timedOut:
            throw LauncherError.runtimeHealthFailed
        }
    }

    private func waitForHealth(_ policy: RuntimeServiceRestartPolicy) throws {
        try waitForHealth(
            restartVM: policy.restartVM,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    private func waitForDatastoreRepairResult(requestId: String) throws {
        log("waiting for datastore repair result timeoutSeconds=\(Constants.Runtime.datastoreRepairWaitTimeoutSeconds)")
        let maxAttempts = Int(ceil(Constants.Runtime.datastoreRepairWaitTimeoutSeconds / 3.0))
        let waitResult = DatastoreRepairWaiter.wait(
            expectedRequestId: requestId,
            configuration: DatastoreRepairWaitConfiguration(
                maxAttempts: maxAttempts,
                progressEveryAttempts: 5
            ),
            loadResult: { guestGateway.loadDatastoreRepairResult() },
            onProgress: { message in
                log(message)
                try? writeRuntimeStatus(
                    .recovering,
                    operation: .repairDatastore,
                    message: message
                )
            },
            onStale: { message in
                log("datastore repair result stale message=\(message)")
            },
            sleep: {
                sleeper.sleep(forTimeInterval: 3)
            }
        )

        switch waitResult {
        case .completed(let message):
            log("datastore repair guest result completed message=\(message)")
            return
        case .failed(let message):
            log("datastore repair guest result failed message=\(message)")
            throw LauncherError.runtimeHealthFailed
        case .timedOut:
            throw LauncherError.runtimeHealthFailed
        }
    }

    private func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        reasons.isEmpty ? "unknown" : reasons.map(\.rawValue).joined(separator: ", ")
    }

    private func rotateRuntimeLogs() throws {
        let logFiles = [
            "launcher.log",
            "launchd.out.log",
            "launchd.err.log",
            "proxy.out.log",
            "proxy.err.log",
            "watchdog.out.log",
            "watchdog.err.log",
        ]

        for fileName in logFiles {
            let logFile = logsDirectory.appendingPathComponent(fileName)
            guard fileExists(logFile),
                  try fileSize(logFile) >= Constants.Runtime.logRotationMaxBytes
            else {
                continue
            }

            for index in stride(from: Constants.Runtime.logRotationKeepCount - 1, through: 1, by: -1) {
                let source = logsDirectory.appendingPathComponent("\(fileName).\(index)")
                let destination = logsDirectory.appendingPathComponent("\(fileName).\(index + 1)")
                if fileExists(destination) {
                    try fileStore.removeItem(at: destination)
                }
                if fileExists(source) {
                    try fileStore.moveItem(at: source, to: destination)
                }
            }

            let rotated = logsDirectory.appendingPathComponent("\(fileName).1")
            if fileExists(rotated) {
                try fileStore.removeItem(at: rotated)
            }
            try fileStore.moveItem(at: logFile, to: rotated)
            try fileStore.writeData(Data(), to: logFile, options: [])
            log("rotated log file=\(logFile.path)")
        }
    }

    private func requireFreeSpace(at url: URL, minimumBytes: UInt64, operation: String) throws {
        let available = try availableBytes(at: url)
        guard available >= minimumBytes else {
            throw LauncherError.insufficientFreeSpace(
                operation: operation,
                required: minimumBytes,
                available: available
            )
        }
        log("free-space preflight passed operation=\(operation) required=\(formatBytes(minimumBytes)) available=\(formatBytes(available))")
    }

    private func requireFreeSpace(at url: URL, minimumBytes: UInt64, operation: RuntimeOperation) throws {
        try requireFreeSpace(at: url, minimumBytes: minimumBytes, operation: operation.rawValue)
    }

    private func availableBytes(at url: URL) throws -> UInt64 {
        let attributes = try fileStore.fileSystemAttributes(forPath: url.path)
        guard attributes.freeBytes > 0 else {
            throw LauncherError.missingArgument("could not determine free space for \(url.path)")
        }
        return attributes.freeBytes
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    private func resizeVMDiskIfNeeded(diskGiB: Int) throws {
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

    private func directorySize(_ url: URL) throws -> UInt64 {
        try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func bundleItemSize(_ bytes: Int) -> UInt64 {
        UInt64(max(bytes, 0))
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now)
    }

    private func log(_ message: String) {
        print("[\(isoTimestamp())] \(message)")
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: clock.now)
    }

    private func runtimeVersionValue() -> String {
        runtimeVersionStore().readVersionValue(default: "unknown")
    }

    private func runtimeStatusValue() -> String {
        statusReporter.statusValue()
    }

    private func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        healthChecker.snapshot()
    }

    private func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try statusReporter.writeStatus(
            status,
            operation: operation,
            message: message,
            updatedAt: isoTimestamp(),
            runtimeVersion: runtimeVersionValue(),
            healthSnapshot: runtimeHealthSnapshot(),
            latestBackup: latestBackup(),
            progress: progress
        )
    }

    private func writeRuntimeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        try statusReporter.writeProgress(
            status,
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: isoTimestamp(),
            runtimeVersion: runtimeVersionValue(),
            healthSnapshot: runtimeHealthSnapshot(),
            latestBackup: latestBackup()
        )
    }

    private func fileState(path: String) -> String {
        healthChecker.fileState(path: path)
    }

    private func fileState(url: URL) -> String {
        healthChecker.fileState(url: url)
    }

    private func launchdState(_ label: String) -> String {
        healthChecker.launchdState(label)
    }

    private func installedProxyPort() -> Int {
        healthChecker.installedProxyPort()
    }

    private func setInstalledProxyPort(_ port: Int) throws {
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(port)",
                launchDaemonPlist(Constants.Launchd.proxyService),
            ]
        )
    }

    private func readSecretFile(_ url: URL) throws -> String {
        guard url.path.hasPrefix("/private/tmp/") || url.path.hasPrefix("/tmp/") else {
            throw LauncherError.missingArgument("--admin-password-file must be under /private/tmp")
        }
        let data = try fileStore.readData(url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw LauncherError.missingArgument("--admin-password-file must be UTF-8")
        }
        return value
    }

    private func restrictSecretFile(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0600", url.path])
    }

    private func setStartOnBoot(_ enabled: Bool) throws {
        try serviceController.setStartOnBoot(enabled)
    }

    private func guestRuntimeState() -> GuestRuntimeStateDocument? {
        healthChecker.guestRuntimeState()
    }

    private func runProcess(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        commandRunner.run(executable, arguments: arguments)
    }

    private func runRequired(_ executable: String, arguments: [String]) throws {
        log("command started executable=\(executable) arguments=\(arguments.joined(separator: " "))")
        let result = runProcess(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                log("command stderr executable=\(executable) stderr=\(stderr)")
            }
            log("command failed executable=\(executable) exitCode=\(result.exitCode)")
            throw LauncherError.missingArgument(
                "command failed: \(([executable] + arguments).joined(separator: " "))"
            )
        }
        log("command completed executable=\(executable)")
    }

    private func runProcessToFile(_ executable: String, arguments: [String], output: URL) throws {
        let result = commandRunner.runWritingOutput(executable, arguments: arguments, output: output)
        guard result.exitCode == 0 else {
            let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderrText.isEmpty {
                log("command stderr executable=\(executable) stderr=\(stderrText)")
            }
            log("command failed executable=\(executable) exitCode=\(result.exitCode)")
            throw LauncherError.missingArgument(
                "command failed: \(([executable] + arguments).joined(separator: " "))"
            )
        }
    }

    private func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private func readTrimmed(_ url: URL) -> String? {
        healthChecker.readTrimmed(url)
    }

    private func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }
}
