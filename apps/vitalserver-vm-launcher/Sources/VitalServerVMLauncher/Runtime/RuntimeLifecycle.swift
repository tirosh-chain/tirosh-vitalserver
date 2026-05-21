import CryptoKit
import Foundation

struct RuntimeLifecycle {
    let paths: LauncherPaths

    private var productRoot: URL {
        paths.home.deletingLastPathComponent()
    }

    private var bundlesDirectory: URL {
        productRoot.appendingPathComponent(Constants.Paths.bundlesDirectory)
    }

    private var backupsDirectory: URL {
        productRoot.appendingPathComponent(Constants.Paths.backupsDirectory)
    }

    private var statusDirectory: URL {
        productRoot.appendingPathComponent(Constants.Paths.statusDirectory)
    }

    private var logsDirectory: URL {
        paths.home.appendingPathComponent(Constants.Paths.logsDirectory)
    }

    private var runtimeStatus: URL {
        statusDirectory.appendingPathComponent(Constants.Artifacts.runtimeStatus)
    }

    private var rootfsBase: URL {
        paths.home
            .appendingPathComponent(Constants.Paths.runtimeDirectory)
            .appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    private var vmDisk: URL {
        paths.home
            .appendingPathComponent(Constants.Paths.runtimeDirectory)
            .appendingPathComponent(Constants.BootAssets.disk)
    }

    private var runtimeVersion: URL {
        paths.home
            .appendingPathComponent(Constants.Paths.runtimeDirectory)
            .appendingPathComponent(Constants.Artifacts.runtimeVersion)
    }

    private var vmIPFile: URL {
        paths.home
            .appendingPathComponent(Constants.Paths.dataDirectory)
            .appendingPathComponent(Constants.Paths.runDirectory)
            .appendingPathComponent(Constants.Runtime.vmIPFile)
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
              vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--vital-files-dir <path>] [--public-host <host>] [--public-port <port>] [--admin-password <password>] [--start-on-boot true|false] [--restart]
              vitalserver-vm runtime configure [--admin-password-file <path>] [--restart]
              vitalserver-vm runtime verify-bundle <bundle-dir>
              vitalserver-vm runtime stage-bundle <bundle-dir>
              vitalserver-vm runtime apply-bundle <bundle-dir>
              vitalserver-vm runtime rollback [backup-dir]
            """
        )
    }

    func install() throws {
        let defaultVitalFilesDirectory = paths.home
            .appendingPathComponent(Constants.Paths.dataDirectory)
            .appendingPathComponent(Constants.Paths.vitalFilesDirectory)
            .path
        let settings = try InstallSettings.load(defaultVitalFilesDirectory: defaultVitalFilesDirectory)
        log("runtime install started home=\(paths.home.path)")
        try writeRuntimeStatus(.installing, operation: "install", message: "runtime install started")
        do {
            try runStep("load-install-settings") {
                log("install settings loaded")
            }
            try runStep("prepare-install-directories") {
                try prepareInstallDirectories(settings)
            }
            try runStep("rotate-runtime-logs") {
                try rotateRuntimeLogs()
            }
            try runStep("configure-guest-runtime-config") {
                try configureDeployEnvironment(settings)
            }
            try runStep("prepare-installed-executables") {
                try prepareInstalledExecutables()
            }
            try runStep("provision-vm-disk") {
                try provisionVMDisk(settings)
            }
            try runStep("configure-vm-runtime") {
                try configureInstalledVMRuntime(settings)
            }
            try runStep("create-cloud-init-seed") {
                try createCloudInitSeed(settings)
            }
            try runStep("write-runtime-version") {
                try writeInstalledRuntimeVersion()
            }
            try runStep("configure-installed-permissions") {
                try configureInstalledPermissions(settings)
            }
            try runStep("start-installed-services") {
                try startInstalledServices(settings)
            }
            try runStep("apply-start-on-boot-policy") {
                try applyStartOnBootPolicy(settings)
            }
            try runStep("cleanup-install-settings") {
                try cleanupInstallSettings()
            }
            try writeRuntimeStatus(.healthy, operation: "install", message: "runtime install completed")
            log("runtime install completed home=\(paths.home.path)")
        } catch {
            try? writeRuntimeStatus(.critical, operation: "install", message: "runtime install failed: \(error)")
            throw error
        }
    }

    func printStatus() {
        print("Tirosh VitalServer runtime")
        print("  product root: \(productRoot.path)")
        print("  runtime dir: \(paths.home.appendingPathComponent(Constants.Paths.runtimeDirectory).path)")
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
        print("  VM IP: \(readTrimmed(vmIPFile) ?? "waiting")")
        let proxyPort = installedProxyPort()
        print("  proxy port: \(proxyPort)")
        print("  host proxy HTTP: \(httpStatus(Constants.Runtime.proxyHealthURL(port: proxyPort)))")
    }

    private func prepareInstallDirectories(_ settings: InstallSettings) throws {
        let data = paths.home.appendingPathComponent(Constants.Paths.dataDirectory)
        let directories = [
            paths.home.appendingPathComponent(Constants.Paths.runtimeDirectory),
            URL(fileURLWithPath: settings.vitalFilesDirectory),
            data.appendingPathComponent("deploy"),
            data.appendingPathComponent(Constants.Paths.runDirectory),
            data.appendingPathComponent(Constants.Paths.vrReleaseDirectory),
            paths.home.appendingPathComponent(Constants.Paths.logsDirectory),
            paths.home.appendingPathComponent(Constants.Paths.runDirectory),
            statusDirectory,
            URL(fileURLWithPath: "\(productRoot.path)/nginx/logs"),
        ]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func configureDeployEnvironment(_ settings: InstallSettings) throws {
        let runtimeConfig = paths.home
            .appendingPathComponent(Constants.Paths.dataDirectory)
            .appendingPathComponent("deploy")
            .appendingPathComponent(Constants.Artifacts.runtimeConfig)
        let document = GuestRuntimeConfigDocument(
            vitalserverHttpPort: 18080,
            redisHost: "redis",
            redisPort: 6379,
            trustProxy: true,
            publicHost: settings.publicHost,
            publicPort: settings.publicPort,
            adminPassword: settings.adminPassword ?? "admin",
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisUiPort: 18081,
            swaggerUiPort: 18082
        )
        let data = try JSONEncoder.pretty.encode(document)
        try data.write(to: runtimeConfig, options: .atomic)
        try restrictSecretFile(runtimeConfig)
    }

    private func prepareInstalledExecutables() throws {
        for path in [
            Constants.InstallPaths.vmBin,
            Constants.InstallPaths.proxyRun,
            "\(productRoot.path)/nginx/sbin/nginx",
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
                try FileManager.default.removeItem(at: temporary)
            }
            try runProcessToFile(
                Constants.Commands.gunzip,
                arguments: ["-c", rootfsBase.path],
                output: temporary
            )
            try FileManager.default.moveItem(at: temporary, to: vmDisk)
            log("created vm disk path=\(vmDisk.path) source=\(rootfsBase.lastPathComponent)")
        }
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(rootfsBase.path)
        }
        try runRequired(Constants.Commands.truncate, arguments: ["-s", "\(settings.diskGiB)G", vmDisk.path])
    }

    private func configureInstalledVMRuntime(_ settings: InstallSettings) throws {
        let data = paths.home.appendingPathComponent(Constants.Paths.dataDirectory)
        try FileManager.default.createDirectory(
            at: paths.home.appendingPathComponent(Constants.Paths.runtimeDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: data.appendingPathComponent(Constants.Paths.vitalFilesDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: data.appendingPathComponent(Constants.Paths.vrReleaseDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: paths.home.appendingPathComponent(Constants.Paths.runDirectory),
            withIntermediateDirectories: true
        )

        var config: VMRuntimeConfig
        if fileExists(paths.config) {
            config = try VMRuntimeConfig.load(from: paths.config)
        } else {
            config = VMRuntimeConfig.default(home: paths.home)
        }
        config.cpuCount = settings.cpuCount
        config.memoryMiB = UInt64(settings.memoryGiB * 1024)
        config.network.mode = settings.networkMode
        if settings.networkMode == .shared {
            config.network.bridgedInterface = nil
        }
        config.sharedDirectory = SharedDirectoryConfig(
            hostPath: data.path,
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
        VMRuntimeConfig.ensureRuntimeDefaults(&config, home: paths.home)
        let encoded = try JSONEncoder.pretty.encode(config)
        try FileManager.default.createDirectory(at: paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: paths.config)
    }

    private func createCloudInitSeed(_ settings: InstallSettings) throws {
        let runtime = paths.home.appendingPathComponent(Constants.Paths.runtimeDirectory)
        let seedDir = runtime.appendingPathComponent("cloud-init-seed")
        let seedISO = runtime.appendingPathComponent(Constants.BootAssets.cloudInit)
        if directoryExists(seedDir) {
            try FileManager.default.removeItem(at: seedDir)
        }
        try FileManager.default.createDirectory(at: seedDir, withIntermediateDirectories: true)
        let instanceID = "tirosh-\(UUID().uuidString.lowercased())"
        try """
        instance-id: \(instanceID)
        local-hostname: \(settings.vmHostname)

        """.write(to: seedDir.appendingPathComponent("meta-data"), atomically: true, encoding: .utf8)

        try """
        #cloud-config
        hostname: \(settings.vmHostname)
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
          - test -x /mnt/tirosh/deploy/bootstrap.sh
          - /mnt/tirosh/deploy/bootstrap.sh

        """.write(to: seedDir.appendingPathComponent("user-data"), atomically: true, encoding: .utf8)

        if fileExists(seedISO) {
            try FileManager.default.removeItem(at: seedISO)
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
            product: "TiroshVitalServer",
            runtimeVersion: Constants.launcherVersion,
            installedAt: isoTimestamp(),
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk
        )
        let data = try JSONEncoder.pretty.encode(document)
        try FileManager.default.createDirectory(at: runtimeVersion.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: runtimeVersion)
    }

    private func configureInstalledPermissions(_ settings: InstallSettings) throws {
        try runRequired(Constants.Commands.chown, arguments: ["-R", "root:wheel", paths.home.path])
        try runRequired(Constants.Commands.chown, arguments: ["-R", "root:wheel", "\(productRoot.path)/nginx"])
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(settings.proxyPort)",
                "/Library/LaunchDaemons/\(Constants.Launchd.proxyService).plist",
            ]
        )
        for plist in [
            "/Library/LaunchDaemons/\(Constants.Launchd.vmService).plist",
            "/Library/LaunchDaemons/\(Constants.Launchd.proxyService).plist",
            "/Library/LaunchDaemons/\(Constants.Launchd.watchdogService).plist",
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
            try FileManager.default.removeItem(at: settingsFile)
        }
    }

    func health() throws {
        printStatus()
        let snapshot = runtimeHealthSnapshot()
        let failed = !snapshot.isHealthy

        if failed {
            try? writeRuntimeStatus(
                .degraded,
                operation: "health",
                message: "runtime health check failed: \(snapshot.failureReasons.joined(separator: ", "))"
            )
            print("health: failed")
            throw LauncherError.runtimeHealthFailed
        }
        try writeRuntimeStatus(.healthy, operation: "health", message: "runtime health check passed")
        print("health: ok")
    }

    func watchdog() throws {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? rotateRuntimeLogs()

        let initial = runtimeHealthSnapshot()
        guard !initial.isHealthy else {
            try writeRuntimeStatus(.healthy, operation: "watchdog", message: "runtime watchdog passed")
            print("watchdog: ok")
            return
        }

        let reasons = initial.failureReasons.joined(separator: ", ")
        log("watchdog detected unhealthy runtime reasons=\(reasons)")
        try writeRuntimeStatus(.recovering, operation: "watchdog", message: "watchdog recovery started: \(reasons)")

        if !FileManager.default.isExecutableFile(atPath: Constants.InstallPaths.vmBin)
            || !FileManager.default.isExecutableFile(atPath: Constants.InstallPaths.proxyRun)
            || !fileExists(rootfsBase)
            || !fileExists(vmDisk) {
            try writeRuntimeStatus(.critical, operation: "watchdog", message: "watchdog cannot recover missing installed artifacts: \(reasons)")
            print("watchdog: critical")
            return
        }

        if initial.vmService != "loaded" || initial.vmIP == nil || !isSuccessfulHTTPStatus(initial.guestHTTP) {
            restartLaunchdService(Constants.Launchd.vmService)
        }
        if initial.proxyService != "loaded" || !isSuccessfulHTTPStatus(initial.hostProxyHTTP) {
            restartLaunchdService(Constants.Launchd.proxyService)
        }

        Thread.sleep(forTimeInterval: Constants.Runtime.watchdogRecoveryWaitSeconds)
        let recovered = runtimeHealthSnapshot()
        if recovered.isHealthy {
            try writeRuntimeStatus(.healthy, operation: "watchdog", message: "watchdog recovery completed")
            print("watchdog: recovered")
        } else {
            try writeRuntimeStatus(
                .critical,
                operation: "watchdog",
                message: "watchdog recovery failed: \(recovered.failureReasons.joined(separator: ", "))"
            )
            print("watchdog: critical")
        }
    }

    func configure(arguments: [String]) throws {
        var remaining = arguments
        var restart = false
        var vmConfig = try VMRuntimeConfig.load(from: paths.config)
        let runtimeConfigURL = paths.home
            .appendingPathComponent(Constants.Paths.dataDirectory)
            .appendingPathComponent("deploy")
            .appendingPathComponent(Constants.Artifacts.runtimeConfig)
        var guestConfig = try GuestRuntimeConfigDocument.load(from: runtimeConfigURL)

        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            if key == "--restart" {
                restart = true
                continue
            }
            guard let value = remaining.first else {
                throw LauncherError.missingArgument("missing value for \(key)")
            }
            remaining.removeFirst()

            switch key {
            case "--cpu":
                guard let cpu = Int(value),
                      cpu >= Constants.Defaults.minimumCPUCount,
                      cpu <= Constants.Defaults.maximumCPUCount else {
                    throw LauncherError.missingArgument(
                        "--cpu must be between \(Constants.Defaults.minimumCPUCount) and \(Constants.Defaults.maximumCPUCount)"
                    )
                }
                vmConfig.cpuCount = cpu
            case "--memory-gib":
                guard let memoryGiB = UInt64(value),
                      stride(from: 4, through: 64, by: 4).contains(Int(memoryGiB)) else {
                    throw LauncherError.missingArgument("--memory-gib must be between 4 and 64 in 4 GiB steps")
                }
                vmConfig.memoryMiB = memoryGiB * 1024
            case "--network":
                guard let mode = NetworkMode(rawValue: value) else {
                    throw LauncherError.missingArgument("--network must be `shared` or `bridged`")
                }
                vmConfig.network.mode = mode
                if mode == .shared {
                    vmConfig.network.bridgedInterface = nil
                }
            case "--bridged-interface":
                guard isLineSafe(value), !value.isEmpty else {
                    throw LauncherError.missingArgument("--bridged-interface must not be empty or contain newlines")
                }
                vmConfig.network.bridgedInterface = value
            case "--proxy-port":
                guard let port = Int(value), (1...65_535).contains(port) else {
                    throw LauncherError.missingArgument("--proxy-port must be between 1 and 65535")
                }
                try setInstalledProxyPort(port)
            case "--vital-files-dir":
                guard value.hasPrefix("/") else {
                    throw LauncherError.missingArgument("--vital-files-dir must be an absolute path")
                }
                try FileManager.default.createDirectory(atPath: value, withIntermediateDirectories: true)
                vmConfig.vitalFilesDirectory = SharedDirectoryConfig(
                    hostPath: value,
                    tag: Constants.Defaults.vitalFilesDirectoryTag,
                    guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                    readOnly: false
                )
                guestConfig.vitalFilesDirectory = Constants.Defaults.vitalFilesDirectoryGuestMountPath
            case "--public-host":
                guard isLineSafe(value) else {
                    throw LauncherError.missingArgument("--public-host must not contain newlines")
                }
                guestConfig.publicHost = value
            case "--public-port":
                guard let port = Int(value), (1...65_535).contains(port) else {
                    throw LauncherError.missingArgument("--public-port must be between 1 and 65535")
                }
                guestConfig.publicPort = port
            case "--admin-password":
                guard !value.isEmpty, isLineSafe(value) else {
                    throw LauncherError.missingArgument("--admin-password must not be empty or contain newlines")
                }
                guestConfig.adminPassword = value
            case "--admin-password-file":
                let password = try readSecretFile(URL(fileURLWithPath: value))
                guard !password.isEmpty, isLineSafe(password) else {
                    throw LauncherError.missingArgument("--admin-password-file must contain a non-empty single-line password")
                }
                guestConfig.adminPassword = password
            case "--start-on-boot":
                guard let enabled = parseBool(value) else {
                    throw LauncherError.missingArgument("--start-on-boot must be true or false")
                }
                try setStartOnBoot(enabled)
            default:
                throw LauncherError.missingArgument("unsupported runtime configure option: \(key)")
            }
        }

        if vmConfig.network.mode == .bridged,
           vmConfig.network.bridgedInterface?.isEmpty != false {
            throw LauncherError.missingArgument("--bridged-interface is required when --network bridged")
        }

        VMRuntimeConfig.ensureRuntimeDefaults(&vmConfig, home: paths.home)
        try JSONEncoder.pretty.encode(vmConfig).write(to: paths.config, options: .atomic)
        try JSONEncoder.pretty.encode(guestConfig).write(to: runtimeConfigURL, options: .atomic)
        try restrictSecretFile(runtimeConfigURL)
        try writeRuntimeStatus(.degraded, operation: "configure", message: "runtime configuration updated")
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
        guard manifest.schemaVersion == 2 else {
            throw LauncherError.missingArgument("unsupported bundle schema: \(manifest.schemaVersion)")
        }
        guard manifest.product == "TiroshVitalServer" else {
            throw LauncherError.missingArgument("unsupported bundle product: \(manifest.product)")
        }

        let checksumMap = try loadChecksums(checksumsURL)
        for artifact in manifest.artifacts {
            guard isSafeBundleName(artifact.name) else {
                throw LauncherError.missingArgument("invalid artifact name: \(artifact.name)")
            }
            let artifactURL = bundleURL.appendingPathComponent(artifact.name)
            guard fileExists(artifactURL) else {
                throw LauncherError.missingFile(artifactURL.path)
            }

            try verifyDigestedFile(
                artifactURL,
                checksumKey: artifact.name,
                expectedSHA256: artifact.sha256,
                expectedSize: artifact.size,
                checksumMap: checksumMap
            )
            try validateUpdateArtifactPayload(artifact, source: artifactURL)
        }

        for migration in manifest.migrations {
            guard isSafeBundleName(migration.name) else {
                throw LauncherError.missingArgument("invalid migration name: \(migration.name)")
            }
            let checksumKey = "migrations/\(migration.name)"
            let migrationURL = bundleURL.appendingPathComponent(checksumKey)
            guard fileExists(migrationURL) else {
                throw LauncherError.missingFile(migrationURL.path)
            }

            try verifyDigestedFile(
                migrationURL,
                checksumKey: checksumKey,
                expectedSHA256: migration.sha256,
                expectedSize: migration.size,
                checksumMap: checksumMap
            )
        }

        print("bundle verified: \(bundleURL.path)")
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        try verifyBundle(bundleURL)
        let manifest = try loadManifest(bundleURL.appendingPathComponent(Constants.Bundle.manifest))
        let destination = bundlesDirectory.appendingPathComponent("update-bundle-\(manifest.version)")

        try FileManager.default.createDirectory(at: bundlesDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try requireFreeSpace(
            at: bundlesDirectory,
            minimumBytes: (try directorySize(bundleURL)) + Constants.Runtime.updateFreeSpaceMarginBytes,
            operation: "stage-bundle"
        )
        try FileManager.default.copyItem(at: bundleURL, to: destination)
        print("bundle staged: \(destination.path)")
        return destination
    }

    func applyBundle(_ bundleURL: URL) throws {
        log("bundle apply started input=\(bundleURL.path)")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? rotateRuntimeLogs()
        try writeRuntimeStatus(.updating, operation: "apply-bundle", message: "bundle apply started")

        let stagedBundle: URL
        let manifest: UpdateBundleManifest
        let stagedRootfs: URL
        let restartVM: Bool
        let restartProxy: Bool
        let restartWatchdog: Bool
        let backup: URL

        do {
            stagedBundle = try stageBundle(bundleURL)
            manifest = try loadManifest(stagedBundle.appendingPathComponent(Constants.Bundle.manifest))
            stagedRootfs = stagedBundle.appendingPathComponent(Constants.Artifacts.rootfsBase)
            guard fileExists(stagedRootfs) else {
                throw LauncherError.missingFile(stagedRootfs.path)
            }

            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try requireFreeSpace(
                at: backupsDirectory,
                minimumBytes: (try fileSize(rootfsBase)) + (try fileSize(stagedRootfs)) + Constants.Runtime.updateFreeSpaceMarginBytes,
                operation: "apply-bundle"
            )

            restartVM = isLaunchdLoaded(Constants.Launchd.vmService)
            restartProxy = isLaunchdLoaded(Constants.Launchd.proxyService)
            restartWatchdog = isLaunchdLoaded(Constants.Launchd.watchdogService)
            backup = try createBackup(reason: "before-\(manifest.version)")
            log("backup created path=\(backup.path)")
        } catch {
            try? writeRuntimeStatus(.critical, operation: "apply-bundle", message: "bundle apply preflight failed: \(error)")
            throw error
        }

        do {
            try runStep("stop-runtime-services") {
                try stopRuntimeServices()
            }
            try runStep("replace-rootfs-base") {
                try FileManager.default.createDirectory(
                    at: rootfsBase.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try replaceFile(from: stagedRootfs, to: rootfsBase)
            }
            try runStep("replace-update-artifacts") {
                try replaceUpdateArtifacts(manifest.artifacts, stagedBundle: stagedBundle)
            }
            try runStep("run-migrations") {
                try runMigrations(manifest.migrations, stagedBundle: stagedBundle)
            }
            try runStep("write-runtime-version") {
                try writeRuntimeVersion(version: manifest.version, bundle: stagedBundle)
            }
            try runStep("start-runtime-services") {
                try startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy, restartWatchdog: restartWatchdog)
            }
            try runStep("wait-runtime-health") {
                try waitForHealth(restartVM: restartVM, restartProxy: restartProxy, restartWatchdog: restartWatchdog)
            }
        } catch {
            log("bundle apply failed; rolling back error=\(error)")
            try? writeRuntimeStatus(.recovering, operation: "apply-bundle", message: "bundle apply failed; rolling back: \(error)")
            do {
                try rollback(backup)
                try startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy, restartWatchdog: restartWatchdog)
                try? writeRuntimeStatus(.degraded, operation: "apply-bundle", message: "bundle apply failed; rollback completed: \(error)")
            } catch {
                log("bundle apply rollback failed error=\(error)")
                try? startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy, restartWatchdog: restartWatchdog)
                try? writeRuntimeStatus(.critical, operation: "apply-bundle", message: "bundle apply failed and rollback failed: \(error)")
            }
            throw error
        }

        try writeRuntimeStatus(.healthy, operation: "apply-bundle", message: "bundle applied: \(manifest.version)")
        try pruneOldRuntimeArtifacts()
        log("bundle applied path=\(stagedBundle.path)")
        log("mutable VM disk preserved path=\(vmDisk.path)")
    }

    func rollback(_ requestedBackup: URL?) throws {
        let backup = try requestedBackup ?? requireLatestBackup()
        log("rollback started backup=\(backup.path)")
        try writeRuntimeStatus(.recovering, operation: "rollback", message: "rollback started")
        let backupRootfs = backup.appendingPathComponent(Constants.Artifacts.rootfsBase)
        let backupVersion = backup.appendingPathComponent(Constants.Artifacts.runtimeVersion)
        guard directoryExists(backup) else {
            throw LauncherError.missingFile(backup.path)
        }
        guard fileExists(backupRootfs) else {
            throw LauncherError.missingFile(backupRootfs.path)
        }

        let restartVM = isLaunchdLoaded(Constants.Launchd.vmService)
        let restartProxy = isLaunchdLoaded(Constants.Launchd.proxyService)
        let restartWatchdog = isLaunchdLoaded(Constants.Launchd.watchdogService)
        try runStep("rollback-stop-runtime-services") {
            try stopRuntimeServices()
        }
        try runStep("rollback-restore-rootfs-base") {
            try replaceFile(from: backupRootfs, to: rootfsBase)
        }
        try runStep("rollback-restore-runtime-version") {
            if fileExists(backupVersion) {
                try replaceFile(from: backupVersion, to: runtimeVersion)
            } else {
                try writeRuntimeVersion(version: "rolled-back", bundle: backup)
            }
        }
        try runStep("rollback-restore-update-artifacts") {
            try restoreBackupPathIfExists(
                backup.appendingPathComponent("app-bundle"),
                to: URL(fileURLWithPath: "/Applications/Tirosh VitalServer Manager.app")
            )
            try restoreBackupPathIfExists(
                backup.appendingPathComponent("nginx-bundle"),
                to: productRoot.appendingPathComponent("nginx")
            )
            try restoreBackupPathIfExists(
                backup.appendingPathComponent("guest-deploy"),
                to: paths.home
                    .appendingPathComponent(Constants.Paths.dataDirectory)
                    .appendingPathComponent("deploy")
            )
            try restoreRuntimeToolsIfExists(backup.appendingPathComponent("runtime-tools"))
        }
        try runStep("rollback-start-runtime-services") {
            try startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy, restartWatchdog: restartWatchdog)
        }
        try runStep("rollback-wait-runtime-health") {
            try waitForHealth(restartVM: restartVM, restartProxy: restartProxy, restartWatchdog: restartWatchdog)
        }

        try writeRuntimeStatus(.healthy, operation: "rollback", message: "rollback completed")
        log("rollback restored backup=\(backup.path)")
        log("mutable VM disk preserved path=\(vmDisk.path)")
    }

    private func loadManifest(_ url: URL) throws -> UpdateBundleManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
    }

    private func loadChecksums(_ url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
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

    private func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyDigestedFile(
        _ url: URL,
        checksumKey: String,
        expectedSHA256: String,
        expectedSize: Int,
        checksumMap: [String: String]
    ) throws {
        let actualDigest = try sha256(url)
        guard actualDigest == expectedSHA256 else {
            throw LauncherError.bundleVerificationFailed(
                "manifest checksum mismatch for \(checksumKey)"
            )
        }
        guard checksumMap[checksumKey] == actualDigest else {
            throw LauncherError.bundleVerificationFailed(
                "checksums.txt mismatch for \(checksumKey)"
            )
        }

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard size == expectedSize else {
            throw LauncherError.bundleVerificationFailed("size mismatch for \(checksumKey)")
        }
    }

    private func isSafeBundleName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && URL(fileURLWithPath: name).lastPathComponent == name
    }

    private func runMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        guard !migrations.isEmpty else {
            log("no migrations to run")
            return
        }

        let migrationDirectory = stagedBundle.appendingPathComponent("migrations")
        for migration in migrations {
            let migrationURL = migrationDirectory.appendingPathComponent(migration.name)
            guard FileManager.default.isExecutableFile(atPath: migrationURL.path) else {
                throw LauncherError.bundleVerificationFailed(
                    "migration is not executable: \(migration.name)"
                )
            }
            log("running migration name=\(migration.name) path=\(migrationURL.path)")
            try runRequired(migrationURL.path, arguments: [])
        }
    }

    private func replaceUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        for artifact in artifacts where artifact.type != "rootfs-base" {
            let source = stagedBundle.appendingPathComponent(artifact.name)
            try validateUpdateArtifactPayload(artifact, source: source)
            switch artifact.type {
            case "app-bundle":
                try replaceTarGz(
                    source,
                    destination: URL(fileURLWithPath: "/Applications/Tirosh VitalServer Manager.app")
                )
            case "nginx-bundle":
                try replaceTarGz(source, destination: productRoot.appendingPathComponent("nginx"))
            case "guest-deploy":
                try replaceTarGz(
                    source,
                    destination: paths.home
                        .appendingPathComponent(Constants.Paths.dataDirectory)
                        .appendingPathComponent("deploy")
                )
            case "runtime-tools":
                try extractTarGz(source, destination: URL(fileURLWithPath: "/usr/local/bin"))
            default:
                throw LauncherError.bundleVerificationFailed("unsupported artifact type: \(artifact.type)")
            }
        }
    }

    private func validateUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        switch artifact.type {
        case "rootfs-base":
            return
        case "app-bundle":
            try validateTarGz(source, requiredTopLevel: "Tirosh VitalServer Manager.app")
        case "nginx-bundle":
            try validateTarGz(source, requiredTopLevel: "nginx")
        case "guest-deploy":
            try validateTarGz(source, requiredTopLevel: "deploy")
        case "runtime-tools":
            try validateTarGz(
                source,
                allowedRootEntries: [
                    "vitalserver-vm",
                    "vitalserver-proxy-run",
                    "tirosh-vitalserver-uninstall",
                ]
            )
        default:
            throw LauncherError.bundleVerificationFailed("unsupported artifact type: \(artifact.type)")
        }
    }

    private func replaceTarGz(_ source: URL, destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).update")
        if FileManager.default.fileExists(atPath: temporary.path) {
            try FileManager.default.removeItem(at: temporary)
        }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try runRequired(Constants.Commands.tar, arguments: ["-xzf", source.path, "-C", temporary.path, "--strip-components", "1"])
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func extractTarGz(_ source: URL, destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try runRequired(Constants.Commands.tar, arguments: ["-xzf", source.path, "-C", destination.path])
    }

    private func validateTarGz(
        _ source: URL,
        requiredTopLevel: String? = nil,
        allowedRootEntries: Set<String>? = nil
    ) throws {
        let listOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("tirosh-\(UUID().uuidString)-tar-list.txt")
        defer {
            try? FileManager.default.removeItem(at: listOutput)
        }
        try runProcessToFile(Constants.Commands.tar, arguments: ["-tzf", source.path], output: listOutput)
        let entries = try String(contentsOf: listOutput, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else {
            throw LauncherError.bundleVerificationFailed("empty tar.gz: \(source.lastPathComponent)")
        }

        for entry in entries {
            try validateTarEntryName(entry, source: source)
            let rootEntry = entry.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? entry
            if let requiredTopLevel, rootEntry != requiredTopLevel {
                throw LauncherError.bundleVerificationFailed(
                    "unexpected top-level entry in \(source.lastPathComponent): \(rootEntry)"
                )
            }
            if let allowedRootEntries, !allowedRootEntries.contains(rootEntry) {
                throw LauncherError.bundleVerificationFailed(
                    "unexpected root entry in \(source.lastPathComponent): \(rootEntry)"
                )
            }
        }

        let verboseOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("tirosh-\(UUID().uuidString)-tar-verbose.txt")
        defer {
            try? FileManager.default.removeItem(at: verboseOutput)
        }
        try runProcessToFile(Constants.Commands.tar, arguments: ["-tvzf", source.path], output: verboseOutput)
        let verboseText = try String(contentsOf: verboseOutput, encoding: .utf8)
        for line in verboseText.split(separator: "\n") {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw LauncherError.bundleVerificationFailed(
                    "tar.gz must not contain links: \(source.lastPathComponent)"
                )
            }
        }
    }

    private func validateTarEntryName(_ entry: String, source: URL) throws {
        if entry.hasPrefix("/") || entry.contains("\0") {
            throw LauncherError.bundleVerificationFailed("unsafe tar entry in \(source.lastPathComponent): \(entry)")
        }
        let components = entry.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") {
            throw LauncherError.bundleVerificationFailed("path traversal in \(source.lastPathComponent): \(entry)")
        }
    }

    private func createBackup(reason: String) throws -> URL {
        let timestamp = backupTimestamp()
        let backup = backupsDirectory.appendingPathComponent("\(timestamp)-\(reason)")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)

        if fileExists(rootfsBase) {
            try FileManager.default.copyItem(
                at: rootfsBase,
                to: backup.appendingPathComponent(Constants.Artifacts.rootfsBase)
            )
        }
        if fileExists(runtimeVersion) {
            try FileManager.default.copyItem(
                at: runtimeVersion,
                to: backup.appendingPathComponent(Constants.Artifacts.runtimeVersion)
            )
        }
        try backupPathIfExists(
            URL(fileURLWithPath: "/Applications/Tirosh VitalServer Manager.app"),
            to: backup.appendingPathComponent("app-bundle")
        )
        try backupPathIfExists(productRoot.appendingPathComponent("nginx"), to: backup.appendingPathComponent("nginx-bundle"))
        try backupPathIfExists(
            paths.home
                .appendingPathComponent(Constants.Paths.dataDirectory)
                .appendingPathComponent("deploy"),
            to: backup.appendingPathComponent("guest-deploy")
        )
        try backupRuntimeTools(to: backup.appendingPathComponent("runtime-tools"))

        let manifest = BackupManifest(
            product: "TiroshVitalServer",
            createdAt: isoTimestamp(),
            reason: reason,
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk,
            vmDiskPreserved: true
        )
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: backup.appendingPathComponent(Constants.Artifacts.backupManifest))
        return backup
    }

    private func backupPathIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func restoreBackupPathIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func backupRuntimeTools(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for path in [
            Constants.InstallPaths.vmBin,
            Constants.InstallPaths.proxyRun,
            "/usr/local/bin/tirosh-vitalserver-uninstall",
        ] {
            let source = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
            }
        }
    }

    private func restoreRuntimeToolsIfExists(_ source: URL) throws {
        guard directoryExists(source) else {
            return
        }
        let tools = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for tool in tools {
            let destination = URL(fileURLWithPath: "/usr/local/bin").appendingPathComponent(tool.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: tool, to: destination)
            try runRequired(Constants.Commands.chmod, arguments: ["0755", destination.path])
        }
    }

    private func latestBackup() -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true && url.lastPathComponent.contains("-before-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
    }

    private func pruneOldRuntimeArtifacts() throws {
        try pruneOldDirectories(in: backupsDirectory, keep: Constants.Runtime.backupKeepCount, requiredNameFragment: "-before-")
        try pruneOldDirectories(in: bundlesDirectory, keep: Constants.Runtime.stagedBundleKeepCount, requiredNameFragment: "update-bundle-")
    }

    private func pruneOldDirectories(in directory: URL, keep: Int, requiredNameFragment: String) throws {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let directories = contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true && url.lastPathComponent.contains(requiredNameFragment)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in directories.dropLast(keep) {
            try FileManager.default.removeItem(at: directory)
            log("pruned runtime artifact path=\(directory.path)")
        }
    }

    private func requireLatestBackup() throws -> URL {
        guard let backup = latestBackup() else {
            throw LauncherError.missingArgument("no backups available")
        }
        return backup
    }

    private func replaceFile(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp")
        if FileManager.default.fileExists(atPath: temporary.path) {
            try FileManager.default.removeItem(at: temporary)
        }
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func writeRuntimeVersion(version: String, bundle: URL) throws {
        let document = RuntimeVersionDocument(
            product: "TiroshVitalServer",
            runtimeVersion: version,
            appliedAt: isoTimestamp(),
            bundle: bundle.lastPathComponent,
            rootfsBase: Constants.Artifacts.rootfsBase,
            vmDisk: Constants.BootAssets.disk
        )
        let data = try JSONEncoder.pretty.encode(document)
        try data.write(to: runtimeVersion)
    }

    private func isLaunchdLoaded(_ label: String) -> Bool {
        launchdState(label) == "loaded"
    }

    private func stopRuntimeServices() throws {
        log("stopping runtime services")
        if isLaunchdLoaded(Constants.Launchd.watchdogService) {
            _ = runProcess(
                Constants.Commands.launchctl,
                arguments: ["bootout", "system/\(Constants.Launchd.watchdogService)"]
            )
        }
        if isLaunchdLoaded(Constants.Launchd.proxyService) {
            _ = runProcess(
                Constants.Commands.launchctl,
                arguments: ["bootout", "system/\(Constants.Launchd.proxyService)"]
            )
        }
        if isLaunchdLoaded(Constants.Launchd.vmService) {
            _ = runProcess(
                Constants.Commands.launchctl,
                arguments: ["bootout", "system/\(Constants.Launchd.vmService)"]
            )
        }
    }

    private func startRuntimeServices(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        if restartVM {
            log("starting VM service label=\(Constants.Launchd.vmService)")
            startLaunchdService(Constants.Launchd.vmService)
        }
        if restartProxy {
            log("starting proxy service label=\(Constants.Launchd.proxyService)")
            startLaunchdService(Constants.Launchd.proxyService)
        }
        if restartWatchdog {
            log("starting watchdog service label=\(Constants.Launchd.watchdogService)")
            startLaunchdService(Constants.Launchd.watchdogService)
        }
    }

    private func startLaunchdService(_ label: String) {
        let plist = "/Library/LaunchDaemons/\(label).plist"
        log("launchd bootstrap label=\(label) plist=\(plist)")
        let bootstrap = runProcess(
            Constants.Commands.launchctl,
            arguments: ["bootstrap", "system", plist]
        )
        if bootstrap.exitCode != 0 {
            log("launchd bootstrap failed label=\(label) exitCode=\(bootstrap.exitCode); trying kickstart")
            _ = runProcess(
                Constants.Commands.launchctl,
                arguments: ["kickstart", "-k", "system/\(label)"]
            )
        }
    }

    private func restartLaunchdService(_ label: String) {
        log("launchd restart label=\(label)")
        _ = runProcess(
            Constants.Commands.launchctl,
            arguments: ["kickstart", "-k", "system/\(label)"]
        )
        if !isLaunchdLoaded(label) {
            startLaunchdService(label)
        }
    }

    private func waitForHealth(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) throws {
        guard restartVM || restartProxy || restartWatchdog else {
            log("runtime services were not running before apply; skipping health wait")
            return
        }

        let deadline = Date().addingTimeInterval(Constants.Runtime.waitTimeoutSeconds)
        log("waiting for runtime health timeoutSeconds=\(Constants.Runtime.waitTimeoutSeconds)")
        while Date() < deadline {
            if restartVM, !isLaunchdLoaded(Constants.Launchd.vmService) {
                Thread.sleep(forTimeInterval: 3)
                continue
            }
            if restartProxy, !isLaunchdLoaded(Constants.Launchd.proxyService) {
                Thread.sleep(forTimeInterval: 3)
                continue
            }
            if restartWatchdog, !isLaunchdLoaded(Constants.Launchd.watchdogService) {
                Thread.sleep(forTimeInterval: 3)
                continue
            }

            let proxyStatus = httpStatus(Constants.Runtime.proxyHealthURL(port: installedProxyPort()))
            if isSuccessfulHTTPStatus(proxyStatus) {
                log("runtime health ok hostProxyHTTP=\(proxyStatus)")
                return
            }
            Thread.sleep(forTimeInterval: 3)
        }
        throw LauncherError.runtimeHealthFailed
    }

    private func rotateRuntimeLogs() throws {
        let fileManager = FileManager.default
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
                    try fileManager.removeItem(at: destination)
                }
                if fileExists(source) {
                    try fileManager.moveItem(at: source, to: destination)
                }
            }

            let rotated = logsDirectory.appendingPathComponent("\(fileName).1")
            if fileExists(rotated) {
                try fileManager.removeItem(at: rotated)
            }
            try fileManager.moveItem(at: logFile, to: rotated)
            fileManager.createFile(atPath: logFile.path, contents: nil)
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

    private func availableBytes(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        guard let value = attributes[.systemFreeSize] as? NSNumber else {
            throw LauncherError.missingArgument("could not determine free space for \(url.path)")
        }
        return value.uint64Value
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    private func directorySize(_ url: URL) throws -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LauncherError.missingFile(url.path)
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += UInt64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        return String(format: "%.1fGiB", gib)
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func log(_ message: String) {
        print("[\(isoTimestamp())] \(message)")
    }

    private func runStep(_ name: String, _ operation: () throws -> Void) throws {
        log("step=\(name) status=started")
        do {
            try operation()
            log("step=\(name) status=completed")
        } catch {
            log("step=\(name) status=failed error=\(error)")
            throw error
        }
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    private func runtimeVersionValue() -> String {
        guard fileExists(runtimeVersion),
              let data = try? Data(contentsOf: runtimeVersion),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = document["runtimeVersion"] as? String
        else {
            return "unknown"
        }
        return version
    }

    private func runtimeStatusValue() -> String {
        guard fileExists(runtimeStatus),
              let data = try? Data(contentsOf: runtimeStatus),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = document["status"] as? String
        else {
            return "unknown"
        }
        return status
    }

    private func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        let vmExecutable = FileManager.default.isExecutableFile(atPath: Constants.InstallPaths.vmBin)
        let proxyExecutable = FileManager.default.isExecutableFile(atPath: Constants.InstallPaths.proxyRun)
        let rootfsBaseState = fileState(url: rootfsBase)
        let vmDiskState = fileState(url: vmDisk)
        let vmService = launchdState(Constants.Launchd.vmService)
        let proxyService = launchdState(Constants.Launchd.proxyService)
        let watchdogService = launchdState(Constants.Launchd.watchdogService)
        let vmIP = readTrimmed(vmIPFile)
        let proxyPort = installedProxyPort()
        let hostProxyHTTP = httpStatus(Constants.Runtime.proxyHealthURL(port: proxyPort))
        let guestHTTP = vmIP.map { httpStatus("http://\($0)/") } ?? "missing-vm-ip"
        var failureReasons: [String] = []

        if !vmExecutable {
            failureReasons.append("missing-vm-bin")
        }
        if !proxyExecutable {
            failureReasons.append("missing-proxy-runner")
        }
        if rootfsBaseState != "present" {
            failureReasons.append("missing-rootfs-base")
        }
        if vmDiskState != "present" {
            failureReasons.append("missing-vm-disk")
        }
        if vmService != "loaded" {
            failureReasons.append("vm-service-\(vmService)")
        }
        if proxyService != "loaded" {
            failureReasons.append("proxy-service-\(proxyService)")
        }
        if watchdogService != "loaded" {
            failureReasons.append("watchdog-service-\(watchdogService)")
        }
        if !isSuccessfulHTTPStatus(hostProxyHTTP) {
            failureReasons.append("host-proxy-http-\(hostProxyHTTP)")
        }
        if !isSuccessfulHTTPStatus(guestHTTP) {
            failureReasons.append("guest-http-\(guestHTTP)")
        }

        return RuntimeHealthSnapshot(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBaseState,
            vmDisk: vmDiskState,
            vmService: vmService,
            proxyService: proxyService,
            watchdogService: watchdogService,
            vmIP: vmIP,
            proxyPort: proxyPort,
            hostProxyHTTP: hostProxyHTTP,
            guestHTTP: guestHTTP,
            failureReasons: failureReasons
        )
    }

    private func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: String,
        message: String
    ) throws {
        let snapshot = runtimeHealthSnapshot()
        let document = RuntimeStatusDocument(
            product: "TiroshVitalServer",
            status: status.rawValue,
            operation: operation,
            message: message,
            updatedAt: isoTimestamp(),
            productRoot: productRoot.path,
            runtimeHome: paths.home.path,
            runtimeVersion: runtimeVersionValue(),
            vmService: snapshot.vmService,
            proxyService: snapshot.proxyService,
            watchdogService: snapshot.watchdogService,
            vmIP: snapshot.vmIP,
            proxyPort: snapshot.proxyPort,
            hostProxyHTTP: snapshot.hostProxyHTTP,
            guestHTTP: snapshot.guestHTTP,
            rootfsBase: snapshot.rootfsBase,
            vmDisk: snapshot.vmDisk,
            failureReasons: snapshot.failureReasons,
            latestBackup: latestBackup()?.path
        )
        let data = try JSONEncoder.pretty.encode(document)
        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        try data.write(to: runtimeStatus, options: .atomic)
    }

    private func fileState(path: String) -> String {
        if FileManager.default.isExecutableFile(atPath: path) {
            return "executable"
        }
        if FileManager.default.fileExists(atPath: path) {
            return "present"
        }
        return "missing"
    }

    private func fileState(url: URL) -> String {
        fileExists(url) ? "present" : "missing"
    }

    private func launchdState(_ label: String) -> String {
        let result = runProcess(
            Constants.Commands.launchctl,
            arguments: ["print", "system/\(label)"]
        )
        return result.exitCode == 0 ? "loaded" : "not loaded"
    }

    private func installedProxyPort() -> Int {
        let plist = "/Library/LaunchDaemons/\(Constants.Launchd.proxyService).plist"
        let result = runProcess(
            Constants.Commands.plistBuddy,
            arguments: ["-c", "Print :EnvironmentVariables:VITALSERVER_PROXY_PORT", plist]
        )
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0,
              let port = Int(value),
              (1...65_535).contains(port)
        else {
            return InstallSettings.defaultProxyPort
        }
        return port
    }

    private func setInstalledProxyPort(_ port: Int) throws {
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(port)",
                "/Library/LaunchDaemons/\(Constants.Launchd.proxyService).plist",
            ]
        )
    }

    private func readSecretFile(_ url: URL) throws -> String {
        guard url.path.hasPrefix("/private/tmp/") || url.path.hasPrefix("/tmp/") else {
            throw LauncherError.missingArgument("--admin-password-file must be under /private/tmp")
        }
        let data = try Data(contentsOf: url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw LauncherError.missingArgument("--admin-password-file must be UTF-8")
        }
        return value
    }

    private func restrictSecretFile(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0600", url.path])
    }

    private func setStartOnBoot(_ enabled: Bool) throws {
        let action = enabled ? "enable" : "disable"
        for label in [
            Constants.Launchd.vmService,
            Constants.Launchd.proxyService,
            Constants.Launchd.watchdogService,
        ] {
            try runRequired(Constants.Commands.launchctl, arguments: [action, "system/\(label)"])
        }
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func httpStatus(_ url: String) -> String {
        let result = runProcess(
            Constants.Commands.curl,
            arguments: ["-sS", "-I", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 ? code : "failed"
    }

    private func runProcess(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
            return RuntimeProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: output, encoding: .utf8) ?? "",
                stderr: String(data: errorOutput, encoding: .utf8) ?? ""
            )
        } catch {
            return RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
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
        let process = Process()
        let stderr = Pipe()
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: output)
        defer {
            try? outputHandle.close()
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderrText.isEmpty {
                log("command stderr executable=\(executable) stderr=\(stderrText)")
            }
            log("command failed executable=\(executable) exitCode=\(process.terminationStatus)")
            throw LauncherError.missingArgument(
                "command failed: \(([executable] + arguments).joined(separator: " "))"
            )
        }
    }

    private func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 400
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private func readTrimmed(_ url: URL) -> String? {
        guard let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

struct UpdateBundleManifest: Decodable {
    let schemaVersion: Int
    let product: String
    let version: String
    let runtimeVersion: String
    let createdAt: String
    let artifacts: [UpdateBundleArtifact]
    let migrations: [UpdateBundleMigration]
}

struct UpdateBundleArtifact: Decodable {
    let name: String
    let type: String
    let sha256: String
    let size: Int
}

struct UpdateBundleMigration: Decodable {
    let name: String
    let sha256: String
    let size: Int
}

struct RuntimeProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct RuntimeHealthSnapshot {
    let vmExecutable: Bool
    let proxyExecutable: Bool
    let rootfsBase: String
    let vmDisk: String
    let vmService: String
    let proxyService: String
    let watchdogService: String
    let vmIP: String?
    let proxyPort: Int
    let hostProxyHTTP: String
    let guestHTTP: String
    let failureReasons: [String]

    var isHealthy: Bool {
        failureReasons.isEmpty
    }
}

enum RuntimeStatusLevel: String, Encodable {
    case installing
    case updating
    case recovering
    case healthy
    case degraded
    case critical
}

struct RuntimeStatusDocument: Encodable {
    let product: String
    let status: String
    let operation: String
    let message: String
    let updatedAt: String
    let productRoot: String
    let runtimeHome: String
    let runtimeVersion: String
    let vmService: String
    let proxyService: String
    let watchdogService: String
    let vmIP: String?
    let proxyPort: Int
    let hostProxyHTTP: String
    let guestHTTP: String
    let rootfsBase: String
    let vmDisk: String
    let failureReasons: [String]
    let latestBackup: String?
}

struct RuntimeVersionDocument: Encodable {
    let product: String
    let runtimeVersion: String
    let appliedAt: String
    let bundle: String
    let rootfsBase: String
    let vmDisk: String
}

struct InstalledRuntimeVersionDocument: Encodable {
    let product: String
    let runtimeVersion: String
    let installedAt: String
    let rootfsBase: String
    let vmDisk: String
}

struct GuestRuntimeConfigDocument: Codable {
    var vitalserverHttpPort: Int
    var redisHost: String
    var redisPort: Int
    var trustProxy: Bool
    var publicHost: String
    var publicPort: Int
    var adminPassword: String
    var vitalFilesDirectory: String
    var redisUiPort: Int
    var swaggerUiPort: Int

    static func load(from url: URL) throws -> GuestRuntimeConfigDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GuestRuntimeConfigDocument(
                vitalserverHttpPort: 18080,
                redisHost: "redis",
                redisPort: 6379,
                trustProxy: true,
                publicHost: "",
                publicPort: 80,
                adminPassword: "admin",
                vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                redisUiPort: 18081,
                swaggerUiPort: 18082
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
    }
}

struct BackupManifest: Encodable {
    let product: String
    let createdAt: String
    let reason: String
    let rootfsBase: String
    let vmDisk: String
    let vmDiskPreserved: Bool
}

struct InstallSettings {
    static let defaultSettingsPath = "/private/tmp/tirosh-vitalserver-install.json"
    static let defaultProxyPort = 80

    var cpuCount = 8
    var memoryGiB = 8
    var diskGiB = 64
    var networkMode = NetworkMode.shared
    var proxyPort = defaultProxyPort
    var vitalFilesDirectory: String
    var adminPassword: String?
    var vmHostname = "tirosh-vitalserver"
    var publicHost = ""
    var publicPort = 80
    var startAfterInstall = true
    var startOnBoot = true

    static func load(
        path: String = defaultSettingsPath,
        defaultVitalFilesDirectory: String
    ) throws -> InstallSettings {
        var settings = InstallSettings(
            vitalFilesDirectory: defaultVitalFilesDirectory
        )
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return settings
        }
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(InstallSettingsDocument.self, from: data)
        settings.apply(document: document)
        return settings
    }

    private mutating func apply(document: InstallSettingsDocument) {
        if let requestedCPUCount = document.cpuCount,
           requestedCPUCount >= Constants.Defaults.minimumCPUCount,
           requestedCPUCount <= Constants.Defaults.maximumCPUCount {
            cpuCount = requestedCPUCount
        }
        if let requestedMemoryGiB = document.memoryGiB,
           stride(from: 4, through: 64, by: 4).contains(requestedMemoryGiB) {
            memoryGiB = requestedMemoryGiB
        }
        if let requestedDiskGiB = document.diskGiB,
           stride(from: 32, through: 512, by: 16).contains(requestedDiskGiB) {
            diskGiB = requestedDiskGiB
        }
        if let requestedNetworkMode = document.networkMode,
           let mode = NetworkMode(rawValue: requestedNetworkMode) {
            networkMode = mode
        }
        if let requestedProxyPort = document.proxyPort,
           requestedProxyPort >= 1,
           requestedProxyPort <= 65_535 {
            proxyPort = requestedProxyPort
        }
        if let requestedVitalFilesDirectory = document.vitalFilesDirectory,
           requestedVitalFilesDirectory.hasPrefix("/") {
            vitalFilesDirectory = requestedVitalFilesDirectory
        }
        if let requestedAdminPassword = document.adminPassword,
           !requestedAdminPassword.isEmpty {
            adminPassword = requestedAdminPassword
        }
        if let requestedVMHostname = document.vmHostname,
           isValidHostname(requestedVMHostname) {
            vmHostname = requestedVMHostname
        }
        if let requestedPublicHost = document.publicHost,
           isLineSafe(requestedPublicHost) {
            publicHost = requestedPublicHost
        }
        if let requestedPublicPort = document.publicPort,
           requestedPublicPort >= 1,
           requestedPublicPort <= 65_535 {
            publicPort = requestedPublicPort
        }
        if let requestedStartAfterInstall = document.startAfterInstall {
            startAfterInstall = requestedStartAfterInstall
        }
        if let requestedStartOnBoot = document.startOnBoot {
            startOnBoot = requestedStartOnBoot
        }
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private func isValidHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 63 else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let alphanumeric = CharacterSet.alphanumerics
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && value.unicodeScalars.first.map { alphanumeric.contains($0) } == true
    }
}

private struct InstallSettingsDocument: Decodable {
    let cpuCount: Int?
    let memoryGiB: Int?
    let diskGiB: Int?
    let networkMode: String?
    let proxyPort: Int?
    let vitalFilesDirectory: String?
    let adminPassword: String?
    let vmHostname: String?
    let publicHost: String?
    let publicPort: Int?
    let startAfterInstall: Bool?
    let startOnBoot: Bool?
}
