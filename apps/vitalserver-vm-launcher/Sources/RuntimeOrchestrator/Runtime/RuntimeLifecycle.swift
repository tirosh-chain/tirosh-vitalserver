import CryptoKit
import Foundation
import RuntimeCore
import RuntimeInfrastructure

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
        installedPaths.logsDirectory
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
                throw LauncherError.missingArgument("usage: vitalserver-vm runtime verify-bundle <bundle-dir>")
            }
            try verifyBundle(URL(fileURLWithPath: bundlePath))
        case "stage-bundle":
            guard let bundlePath = arguments.dropFirst().first else {
                throw LauncherError.missingArgument("usage: vitalserver-vm runtime stage-bundle <bundle-dir>")
            }
            _ = try stageBundle(URL(fileURLWithPath: bundlePath))
        case "apply-bundle":
            guard let bundlePath = arguments.dropFirst().first else {
                throw LauncherError.missingArgument("usage: vitalserver-vm runtime apply-bundle <bundle-dir>")
            }
            try applyBundle(URL(fileURLWithPath: bundlePath))
        case "rollback":
            let backupPath = arguments.dropFirst().first
            try rollback(backupPath.map { URL(fileURLWithPath: $0) })
        case "repair-datastore":
            try repairDatastore()
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
              vitalserver-vm runtime verify-bundle <bundle-dir>
              vitalserver-vm runtime stage-bundle <bundle-dir>
              vitalserver-vm runtime apply-bundle <bundle-dir>
              vitalserver-vm runtime rollback [backup-dir]
              vitalserver-vm runtime repair-datastore
            """
        )
    }

    func install() throws {
        let defaultVitalFilesDirectory = installedPaths.vitalFilesDirectory.path
        let settings = try InstallSettings.load(
            defaultVitalFilesDirectory: defaultVitalFilesDirectory,
            fileStore: fileStore
        )
        log("runtime install started home=\(paths.home.path)")
        try writeRuntimeStatus(.installing, operation: .install, message: "runtime install started")
        do {
            try runPlan(RuntimeOperationPlans.install, status: .installing) { step in
                try executeInstallStep(step, settings: settings)
            }
            try writeRuntimeStatus(.healthy, operation: .install, message: "runtime install completed")
            log("runtime install completed home=\(paths.home.path)")
        } catch {
            try? writeRuntimeStatus(.critical, operation: .install, message: "runtime install failed: \(error)")
            throw error
        }
    }

    private func executeInstallStep(_ step: RuntimeWorkflowStep, settings: InstallSettings) throws {
        switch step {
        case .loadInstallSettings:
            log("install settings loaded")
        case .prepareInstallDirectories:
            try prepareInstallDirectories(settings)
        case .rotateRuntimeLogs:
            try rotateRuntimeLogs()
        case .configureGuestRuntimeConfig:
            try configureDeployEnvironment(settings)
        case .prepareInstalledExecutables:
            try prepareInstalledExecutables()
        case .provisionVMDisk:
            try provisionVMDisk(settings)
        case .configureVMRuntime:
            try configureInstalledVMRuntime(settings)
        case .createCloudInitSeed:
            try createCloudInitSeed(settings)
        case .writeInstallRuntimeVersion:
            try writeInstalledRuntimeVersion()
        case .configureInstalledPermissions:
            try configureInstalledPermissions(settings)
        case .startInstalledServices:
            try startInstalledServices(settings)
        case .applyStartOnBootPolicy:
            try applyStartOnBootPolicy(settings)
        case .cleanupInstallSettings:
            try cleanupInstallSettings()
        default:
            throw LauncherError.unsupportedCommand("install step \(step.rawValue)")
        }
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

    private func prepareInstallDirectories(_ settings: InstallSettings) throws {
        let directories = [
            installedPaths.runtimeDirectory,
            URL(fileURLWithPath: settings.vitalFilesDirectory),
            installedPaths.deployDirectory,
            installedPaths.guestRunDirectory,
            installedPaths.vrReleaseDirectory,
            installedPaths.logsDirectory,
            installedPaths.hostRunDirectory,
            statusDirectory,
            installedPaths.nginxLogsDirectory,
        ]
        for directory in directories {
            try fileStore.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func configureDeployEnvironment(_ settings: InstallSettings) throws {
        let runtimeConfig = installedPaths.guestRuntimeConfig
        let document = GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            publicHost: settings.publicHost,
            publicPort: settings.publicPort,
            adminPassword: settings.adminPassword ?? Constants.Guest.defaultAdminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort
        )
        let data = try JSONEncoder.pretty.encode(document)
        try fileStore.writeData(data, to: runtimeConfig, options: .atomic)
        try restrictSecretFile(runtimeConfig)
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
        let document = InstalledRuntimeVersionDocument(
            product: Constants.Product.identifier,
            runtimeVersion: Constants.launcherVersion,
            installedAt: isoTimestamp(),
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk
        )
        let data = try JSONEncoder.pretty.encode(document)
        try fileStore.createDirectory(at: runtimeVersion.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(data, to: runtimeVersion, options: [])
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
        try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? rotateRuntimeLogs()

        let initial = runtimeHealthSnapshot()
        guard !initial.isHealthy else {
            try writeRuntimeStatus(.healthy, operation: .watchdog, message: "runtime watchdog passed")
            print("watchdog: ok")
            return
        }

        let reasons = reasonText(initial.failureReasons)
        log("watchdog detected unhealthy runtime reasons=\(reasons)")
        try writeRuntimeStatus(.recovering, operation: .watchdog, message: "watchdog recovery started: \(reasons)")

        if !fileStore.isExecutableFile(atPath: Constants.InstallPaths.vmBin)
            || !fileStore.isExecutableFile(atPath: Constants.InstallPaths.proxyRun)
            || !fileExists(rootfsBase)
            || !fileExists(vmDisk) {
            try writeRuntimeStatus(.critical, operation: .watchdog, message: "watchdog cannot recover missing installed artifacts: \(reasons)")
            print("watchdog: critical")
            return
        }

        if initial.vmService != "loaded" || initial.vmIP == nil || !isSuccessfulHTTPStatus(initial.guestHTTP) {
            restartLaunchdService(Constants.Launchd.vmService)
        }
        if initial.proxyService != "loaded" || !isSuccessfulHTTPStatus(initial.hostProxyHTTP) {
            restartLaunchdService(Constants.Launchd.proxyService)
        }

        sleeper.sleep(forTimeInterval: Constants.Runtime.watchdogRecoveryWaitSeconds)
        let recovered = runtimeHealthSnapshot()
        if recovered.isHealthy {
            try writeRuntimeStatus(.healthy, operation: .watchdog, message: "watchdog recovery completed")
            print("watchdog: recovered")
        } else {
            try writeRuntimeStatus(
                .critical,
                operation: .watchdog,
                message: "watchdog recovery failed: \(reasonText(recovered.failureReasons))"
            )
            print("watchdog: critical")
        }
    }

    func configure(arguments: [String]) throws {
        var remaining = arguments
        var restart = false
        var vmConfig = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        let runtimeConfigURL = installedPaths.guestRuntimeConfig
        var guestConfig = try GuestRuntimeConfigDocument.load(from: runtimeConfigURL, fileStore: fileStore)

        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            let option = RuntimeConfigureOption(rawValue: key)
            if option == .restart {
                restart = true
                continue
            }
            guard let value = remaining.first else {
                throw LauncherError.missingArgument("missing value for \(key)")
            }
            remaining.removeFirst()

            switch option {
            case .cpu:
                guard let cpu = Int(value),
                      cpu >= Constants.Defaults.minimumCPUCount,
                      cpu <= Constants.Defaults.maximumCPUCount else {
                    throw LauncherError.missingArgument(
                        "--cpu must be between \(Constants.Defaults.minimumCPUCount) and \(Constants.Defaults.maximumCPUCount)"
                    )
                }
                vmConfig.cpuCount = cpu
            case .memoryGiB:
                guard let memoryGiB = UInt64(value),
                      stride(
                        from: Constants.Defaults.minimumMemoryGiB,
                        through: Constants.Defaults.maximumMemoryGiB,
                        by: Constants.Defaults.memoryStepGiB
                      ).contains(Int(memoryGiB)) else {
                    throw LauncherError.missingArgument(
                        "--memory-gib must be between \(Constants.Defaults.minimumMemoryGiB) and \(Constants.Defaults.maximumMemoryGiB) in \(Constants.Defaults.memoryStepGiB) GiB steps"
                    )
                }
                vmConfig.memoryMiB = memoryGiB * 1024
            case .diskGiB:
                guard let diskGiB = Int(value),
                      stride(
                        from: Constants.Defaults.minimumDiskGiB,
                        through: Constants.Defaults.maximumDiskGiB,
                        by: Constants.Defaults.diskStepGiB
                      ).contains(diskGiB) else {
                    throw LauncherError.missingArgument(
                        "--disk-gib must be between \(Constants.Defaults.minimumDiskGiB) and \(Constants.Defaults.maximumDiskGiB) in \(Constants.Defaults.diskStepGiB) GiB steps"
                    )
                }
                try resizeVMDiskIfNeeded(diskGiB: diskGiB)
            case .network:
                guard let mode = NetworkMode(rawValue: value) else {
                    throw LauncherError.missingArgument("--network must be `shared` or `bridged`")
                }
                vmConfig.network.mode = mode
                if mode == .shared {
                    vmConfig.network.bridgedInterface = nil
                }
            case .bridgedInterface:
                guard RuntimeTextValidator.isSingleLine(value), !value.isEmpty else {
                    throw LauncherError.missingArgument("--bridged-interface must not be empty or contain newlines")
                }
                vmConfig.network.bridgedInterface = value
            case .proxyPort:
                guard let port = Int(value), (1...65_535).contains(port) else {
                    throw LauncherError.missingArgument("--proxy-port must be between 1 and 65535")
                }
                try setInstalledProxyPort(port)
            case .vitalFilesDirectory:
                guard value.hasPrefix("/") else {
                    throw LauncherError.missingArgument("--vital-files-dir must be an absolute path")
                }
                try fileStore.createDirectory(at: URL(fileURLWithPath: value), withIntermediateDirectories: true)
                vmConfig.vitalFilesDirectory = SharedDirectoryConfig(
                    hostPath: value,
                    tag: Constants.Defaults.vitalFilesDirectoryTag,
                    guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                    readOnly: false
                )
                guestConfig.vitalFilesDirectory = Constants.Defaults.vitalFilesDirectoryGuestMountPath
            case .publicHost:
                guard RuntimeTextValidator.isSingleLine(value) else {
                    throw LauncherError.missingArgument("--public-host must not contain newlines")
                }
                guestConfig.publicHost = value
            case .publicPort:
                guard let port = Int(value), (1...65_535).contains(port) else {
                    throw LauncherError.missingArgument("--public-port must be between 1 and 65535")
                }
                guestConfig.publicPort = port
            case .adminPassword:
                guard !value.isEmpty, RuntimeTextValidator.isSingleLine(value) else {
                    throw LauncherError.missingArgument("--admin-password must not be empty or contain newlines")
                }
                guestConfig.adminPassword = value
            case .adminPasswordFile:
                let password = try readSecretFile(URL(fileURLWithPath: value))
                guard !password.isEmpty, RuntimeTextValidator.isSingleLine(password) else {
                    throw LauncherError.missingArgument("--admin-password-file must contain a non-empty single-line password")
                }
                guestConfig.adminPassword = password
            case .startOnBoot:
                guard let enabled = RuntimeBooleanParser.parse(value) else {
                    throw LauncherError.missingArgument("--start-on-boot must be true or false")
                }
                try setStartOnBoot(enabled)
            case .restart:
                restart = true
            default:
                throw LauncherError.missingArgument("unsupported runtime configure option: \(key)")
            }
        }

        if vmConfig.network.mode == .bridged,
           vmConfig.network.bridgedInterface?.isEmpty != false {
            throw LauncherError.missingArgument("--bridged-interface is required when --network bridged")
        }

        VMRuntimeConfig.ensureRuntimeDefaults(&vmConfig, paths: installedPaths)
        try fileStore.writeData(try JSONEncoder.pretty.encode(vmConfig), to: paths.config, options: .atomic)
        try fileStore.writeData(try JSONEncoder.pretty.encode(guestConfig), to: runtimeConfigURL, options: .atomic)
        try restrictSecretFile(runtimeConfigURL)
        try writeRuntimeStatus(.degraded, operation: .configure, message: "runtime configuration updated")
        log("runtime configuration updated restart=\(restart)")

        guard restart else {
            print("runtime configuration updated; restart required for VM/guest changes")
            return
        }
        restartLaunchdService(Constants.Launchd.vmService)
        restartLaunchdService(Constants.Launchd.proxyService)
        restartLaunchdService(Constants.Launchd.watchdogService)
        print("runtime configuration updated and services restarted")
    }

    func verifyBundle(_ bundleURL: URL) throws {
        log("bundle verification started path=\(bundleURL.path)")
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

        log("bundle verification completed path=\(bundleURL.path)")
        print("bundle verified: \(bundleURL.path)")
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        log("bundle stage started source=\(bundleURL.path)")
        try verifyBundle(bundleURL)
        let manifest = try loadManifest(bundleURL.appendingPathComponent(Constants.Bundle.manifest))
        let destination = bundlesDirectory.appendingPathComponent("update-bundle-\(manifest.version)")
        let bundleSize = try directorySize(bundleURL)

        try fileStore.createDirectory(at: bundlesDirectory, withIntermediateDirectories: true)
        if fileExists(destination) || directoryExists(destination) {
            log("removing existing staged bundle path=\(destination.path)")
            try fileStore.removeItem(at: destination)
        }
        try requireFreeSpace(
            at: bundlesDirectory,
            minimumBytes: bundleSize + Constants.Runtime.updateFreeSpaceMarginBytes,
            operation: .stageBundle
        )
        log(
            "copying bundle to managed storage source=\(bundleURL.path) destination=\(destination.path) size=\(formatBytes(bundleSize))"
        )
        try fileStore.copyItem(at: bundleURL, to: destination)
        log("bundle stage completed destination=\(destination.path)")
        print("bundle staged: \(destination.path)")
        return destination
    }

    func applyBundle(_ bundleURL: URL) throws {
        log("bundle apply started input=\(bundleURL.path)")
        try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? rotateRuntimeLogs()
        try writeRuntimeStatus(.updating, operation: .applyBundle, message: "bundle apply started")

        let initialHealth = runtimeHealthSnapshot()
        if !initialHealth.isHealthy {
            log("bundle apply preflight warning runtime unhealthy reasons=\(reasonText(initialHealth.failureReasons))")
        }

        let preflight: ApplyBundlePreflightContext

        do {
            preflight = try prepareApplyBundlePreflight(bundleURL)
        } catch {
            try? writeRuntimeStatus(.critical, operation: .applyBundle, message: "bundle apply preflight failed: \(error)")
            throw error
        }

        do {
            try runPlan(RuntimeOperationPlans.applyBundle, status: .updating) { step in
                try executeApplyBundleStep(
                    step,
                    preflight: preflight
                )
            }
        } catch {
            log("bundle apply failed; rolling back error=\(error)")
            try? writeRuntimeStatus(.recovering, operation: .applyBundle, message: "bundle apply failed; rolling back: \(error)")
            do {
                try rollback(preflight.backup)
                try startRuntimeServices(preflight.restartPolicy)
                try? writeRuntimeStatus(.degraded, operation: .applyBundle, message: "bundle apply failed; rollback completed: \(error)")
            } catch {
                log("bundle apply rollback failed error=\(error)")
                try? startRuntimeServices(preflight.restartPolicy)
                try? writeRuntimeStatus(.critical, operation: .applyBundle, message: "bundle apply failed and rollback failed: \(error)")
            }
            throw error
        }

        try writeRuntimeStatus(.healthy, operation: .applyBundle, message: "bundle applied: \(preflight.manifest.version)")
        try pruneOldRuntimeArtifacts()
        log("bundle applied path=\(preflight.stagedBundle.path)")
        log("mutable VM disk preserved path=\(vmDisk.path)")
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
                    currentUpdaterVersion: Constants.launcherVersion
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
        log("datastore repair requested")
        try fileStore.createDirectory(at: guestRunDirectory, withIntermediateDirectories: true)
        try? guestGateway.removeDatastoreRepairResult()
        try writeRuntimeStatus(.recovering, operation: .repairDatastore, message: "datastore repair requested")
        let requestId = UUID().uuidString

        try guestGateway.writeDatastoreRepairRequest(requestId: requestId, requestedAt: isoTimestamp())

        if !isLaunchdLoaded(Constants.Launchd.vmService) {
            startLaunchdService(Constants.Launchd.vmService)
        } else {
            restartLaunchdService(Constants.Launchd.vmService)
        }

        try waitForDatastoreRepairResult(requestId: requestId)
        restartLaunchdService(Constants.Launchd.proxyService)
        restartLaunchdService(Constants.Launchd.watchdogService)
        try waitForHealth(restartVM: true, restartProxy: true, restartWatchdog: true)
        try writeRuntimeStatus(.healthy, operation: .repairDatastore, message: "datastore repair completed")
        log("datastore repair completed")
    }

    func rollback(_ requestedBackup: URL?) throws {
        let preflight = try prepareRollbackPreflight(requestedBackup)
        log("rollback started backup=\(preflight.backup.path)")
        try writeRuntimeStatus(.recovering, operation: .rollback, message: "rollback started")

        try runPlan(RuntimeOperationPlans.rollback, status: .recovering) { step in
            try executeRollbackStep(
                step,
                preflight: preflight
            )
        }

        try writeRuntimeStatus(.healthy, operation: .rollback, message: "rollback completed")
        log("rollback restored backup=\(preflight.backup.path)")
        log("mutable VM disk preserved path=\(vmDisk.path)")
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
        let document = RuntimeVersionDocument(
            product: Constants.Product.identifier,
            runtimeVersion: version,
            appliedAt: isoTimestamp(),
            bundle: bundle.lastPathComponent,
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk
        )
        let data = try JSONEncoder.pretty.encode(document)
        try fileStore.writeData(data, to: runtimeVersion, options: [])
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

    private func runPlan(
        _ plan: RuntimeOperationPlan,
        status: RuntimeStatusLevel,
        execute: (RuntimeWorkflowStep) throws -> Void
    ) throws {
        try RuntimeOperationPlanRunner.run(
            plan: plan,
            status: status,
            execute: execute,
            publish: { event in
                log("step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)")
                try? writeRuntimeProgress(
                    event.status,
                    operation: event.operation,
                    step: event.step,
                    stepStatus: event.stepStatus,
                    phase: event.phase,
                    message: event.message
                )
            }
        )
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
        guard fileExists(runtimeVersion),
              let data = try? fileStore.readData(runtimeVersion),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = document["runtimeVersion"] as? String
        else {
            return "unknown"
        }
        return version
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
