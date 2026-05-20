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
        print("install settings loaded")
        try prepareInstallDirectories(settings)
        try configureDeployEnvironment(settings)
        try prepareInstalledExecutables()
        try provisionVMDisk(settings)
        try configureInstalledVMRuntime(settings)
        try createCloudInitSeed(settings)
        try writeInstalledRuntimeVersion()
        try configureInstalledPermissions(settings)
        try startInstalledServices(settings)
        try applyStartOnBootPolicy(settings)
        try cleanupInstallSettings()
        print("runtime install completed")
    }

    func printStatus() {
        print("Tirosh VitalServer runtime")
        print("  product root: \(productRoot.path)")
        print("  runtime dir: \(paths.home.appendingPathComponent(Constants.Paths.runtimeDirectory).path)")
        print("  latest backup: \(latestBackup()?.path ?? "none")")
        print("  launcher: \(fileState(path: Constants.InstallPaths.vmBin))")
        print("  proxy runner: \(fileState(path: Constants.InstallPaths.proxyRun))")
        print("  rootfs base: \(fileState(url: rootfsBase))")
        print("  vm disk: \(fileState(url: vmDisk))")
        print("  version: \(runtimeVersionValue())")
        print("  VM service: \(launchdState(Constants.Launchd.vmService))")
        print("  proxy service: \(launchdState(Constants.Launchd.proxyService))")
        print("  VM IP: \(readTrimmed(vmIPFile) ?? "waiting")")
        print("  host proxy HTTP: \(httpStatus(Constants.Runtime.proxyHealthURL))")
    }

    private func prepareInstallDirectories(_ settings: InstallSettings) throws {
        print("preparing runtime directories")
        let data = paths.home.appendingPathComponent(Constants.Paths.dataDirectory)
        let directories = [
            paths.home.appendingPathComponent(Constants.Paths.runtimeDirectory),
            URL(fileURLWithPath: settings.vitalFilesDirectory),
            data.appendingPathComponent("deploy"),
            data.appendingPathComponent(Constants.Paths.runDirectory),
            data.appendingPathComponent(Constants.Paths.vrReleaseDirectory),
            paths.home.appendingPathComponent(Constants.Paths.logsDirectory),
            paths.home.appendingPathComponent(Constants.Paths.runDirectory),
            URL(fileURLWithPath: "\(productRoot.path)/nginx/logs"),
        ]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func configureDeployEnvironment(_ settings: InstallSettings) throws {
        print("configuring guest runtime config")
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
    }

    private func prepareInstalledExecutables() throws {
        print("preparing installed executables")
        for path in [
            Constants.InstallPaths.vmBin,
            Constants.InstallPaths.proxyRun,
            "\(productRoot.path)/nginx/sbin/nginx",
        ] {
            try runRequired(Constants.Commands.chmod, arguments: ["0755", path])
        }
    }

    private func provisionVMDisk(_ settings: InstallSettings) throws {
        print("provisioning VM disk")
        if !fileExists(vmDisk), fileExists(rootfsBase) {
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
            print("created \(vmDisk.path) from \(rootfsBase.lastPathComponent)")
        }
        guard fileExists(vmDisk) else {
            throw LauncherError.missingFile(rootfsBase.path)
        }
        try runRequired(Constants.Commands.truncate, arguments: ["-s", "\(settings.diskGiB)G", vmDisk.path])
    }

    private func configureInstalledVMRuntime(_ settings: InstallSettings) throws {
        print("configuring VM runtime")
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
        print("creating cloud-init seed")
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
        print("writing runtime version")
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
        print("configuring ownership and launchd plists")
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
        ] {
            try runRequired(Constants.Commands.chmod, arguments: ["0644", plist])
            try runRequired(Constants.Commands.chown, arguments: ["root:wheel", plist])
        }
    }

    private func startInstalledServices(_ settings: InstallSettings) throws {
        guard settings.startAfterInstall else {
            print("start after install disabled")
            return
        }
        print("starting launchd services")
        startLaunchdService(Constants.Launchd.vmService)
        startLaunchdService(Constants.Launchd.proxyService)
    }

    private func applyStartOnBootPolicy(_ settings: InstallSettings) throws {
        guard !settings.startOnBoot else {
            return
        }
        print("disabling start on boot")
        for plist in [
            "/Library/LaunchDaemons/\(Constants.Launchd.vmService).plist",
            "/Library/LaunchDaemons/\(Constants.Launchd.proxyService).plist",
        ] where FileManager.default.fileExists(atPath: plist) {
            try FileManager.default.removeItem(atPath: plist)
        }
    }

    private func cleanupInstallSettings() throws {
        let settingsFile = URL(fileURLWithPath: InstallSettings.defaultSettingsPath)
        if fileExists(settingsFile) {
            try FileManager.default.removeItem(at: settingsFile)
        }
    }

    func health() throws {
        printStatus()
        var failed = false
        failed = failed || !FileManager.default.isExecutableFile(atPath: Constants.InstallPaths.vmBin)
        failed = failed || !FileManager.default.isExecutableFile(atPath: Constants.InstallPaths.proxyRun)
        failed = failed || !fileExists(rootfsBase)
        failed = failed || !fileExists(vmDisk)
        failed = failed || launchdState(Constants.Launchd.vmService) != "loaded"
        failed = failed || launchdState(Constants.Launchd.proxyService) != "loaded"

        let proxyStatus = httpStatus(Constants.Runtime.proxyHealthURL)
        if !isSuccessfulHTTPStatus(proxyStatus) {
            failed = true
        }

        if failed {
            print("health: failed")
            throw LauncherError.runtimeHealthFailed
        }
        print("health: ok")
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
        try FileManager.default.copyItem(at: bundleURL, to: destination)
        print("bundle staged: \(destination.path)")
        return destination
    }

    func applyBundle(_ bundleURL: URL) throws {
        let stagedBundle = try stageBundle(bundleURL)
        let manifest = try loadManifest(stagedBundle.appendingPathComponent(Constants.Bundle.manifest))
        let stagedRootfs = stagedBundle.appendingPathComponent(Constants.Artifacts.rootfsBase)
        guard fileExists(stagedRootfs) else {
            throw LauncherError.missingFile(stagedRootfs.path)
        }

        let restartVM = isLaunchdLoaded(Constants.Launchd.vmService)
        let restartProxy = isLaunchdLoaded(Constants.Launchd.proxyService)
        let backup = try createBackup(reason: "before-\(manifest.version)")

        do {
            try stopRuntimeServices()
            try FileManager.default.createDirectory(
                at: rootfsBase.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try replaceFile(from: stagedRootfs, to: rootfsBase)
            try runMigrations(manifest.migrations, stagedBundle: stagedBundle)
            try writeRuntimeVersion(version: manifest.version, bundle: stagedBundle)
            try startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy)
            try waitForHealth(restartVM: restartVM, restartProxy: restartProxy)
        } catch {
            print("bundle apply failed; rolling back")
            try rollback(backup)
            try startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy)
            throw error
        }

        print("bundle applied: \(stagedBundle.path)")
        print("backup created: \(backup.path)")
        print("mutable VM disk preserved: \(vmDisk.path)")
    }

    func rollback(_ requestedBackup: URL?) throws {
        let backup = try requestedBackup ?? requireLatestBackup()
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
        try stopRuntimeServices()
        try replaceFile(from: backupRootfs, to: rootfsBase)
        if fileExists(backupVersion) {
            try replaceFile(from: backupVersion, to: runtimeVersion)
        } else {
            try writeRuntimeVersion(version: "rolled-back", bundle: backup)
        }
        try startRuntimeServices(restartVM: restartVM, restartProxy: restartProxy)
        try waitForHealth(restartVM: restartVM, restartProxy: restartProxy)

        print("rollback restored: \(backup.path)")
        print("mutable VM disk preserved: \(vmDisk.path)")
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
            print("no migrations to run")
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
            print("running migration: \(migration.name)")
            try runRequired(migrationURL.path, arguments: [])
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
        print("stopping runtime services")
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

    private func startRuntimeServices(restartVM: Bool, restartProxy: Bool) throws {
        if restartVM {
            print("starting VM service")
            startLaunchdService(Constants.Launchd.vmService)
        }
        if restartProxy {
            print("starting proxy service")
            startLaunchdService(Constants.Launchd.proxyService)
        }
    }

    private func startLaunchdService(_ label: String) {
        let plist = "/Library/LaunchDaemons/\(label).plist"
        let bootstrap = runProcess(
            Constants.Commands.launchctl,
            arguments: ["bootstrap", "system", plist]
        )
        if bootstrap.exitCode != 0 {
            _ = runProcess(
                Constants.Commands.launchctl,
                arguments: ["kickstart", "-k", "system/\(label)"]
            )
        }
    }

    private func waitForHealth(restartVM: Bool, restartProxy: Bool) throws {
        guard restartVM || restartProxy else {
            print("runtime services were not running before apply; skipping health wait")
            return
        }

        let deadline = Date().addingTimeInterval(Constants.Runtime.waitTimeoutSeconds)
        print("waiting for runtime health")
        while Date() < deadline {
            if restartVM, !isLaunchdLoaded(Constants.Launchd.vmService) {
                Thread.sleep(forTimeInterval: 3)
                continue
            }
            if restartProxy, !isLaunchdLoaded(Constants.Launchd.proxyService) {
                Thread.sleep(forTimeInterval: 3)
                continue
            }

            let proxyStatus = httpStatus(Constants.Runtime.proxyHealthURL)
            if isSuccessfulHTTPStatus(proxyStatus) {
                print("runtime health ok: host proxy HTTP \(proxyStatus)")
                return
            }
            Thread.sleep(forTimeInterval: 3)
        }
        throw LauncherError.runtimeHealthFailed
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
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
            return RuntimeProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: output, encoding: .utf8) ?? ""
            )
        } catch {
            return RuntimeProcessResult(exitCode: 127, stdout: "")
        }
    }

    private func runRequired(_ executable: String, arguments: [String]) throws {
        let result = runProcess(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw LauncherError.missingArgument(
                "command failed: \(([executable] + arguments).joined(separator: " "))"
            )
        }
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

struct GuestRuntimeConfigDocument: Encodable {
    let vitalserverHttpPort: Int
    let redisHost: String
    let redisPort: Int
    let trustProxy: Bool
    let publicHost: String
    let publicPort: Int
    let adminPassword: String
    let vitalFilesDirectory: String
    let redisUiPort: Int
    let swaggerUiPort: Int
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

    var cpuCount = 8
    var memoryGiB = 8
    var diskGiB = 64
    var networkMode = NetworkMode.shared
    var proxyPort = 80
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
        if document.cpuCount >= Constants.Defaults.minimumCPUCount,
           document.cpuCount <= Constants.Defaults.maximumCPUCount {
            cpuCount = document.cpuCount
        }
        if stride(from: 4, through: 64, by: 4).contains(document.memoryGiB) {
            memoryGiB = document.memoryGiB
        }
        if stride(from: 32, through: 512, by: 16).contains(document.diskGiB) {
            diskGiB = document.diskGiB
        }
        if let mode = NetworkMode(rawValue: document.networkMode) {
            networkMode = mode
        }
        if document.proxyPort >= 1, document.proxyPort <= 65_535 {
            proxyPort = document.proxyPort
        }
        if document.vitalFilesDirectory.hasPrefix("/") {
            vitalFilesDirectory = document.vitalFilesDirectory
        }
        if !document.adminPassword.isEmpty {
            adminPassword = document.adminPassword
        }
        if isValidHostname(document.vmHostname) {
            vmHostname = document.vmHostname
        }
        if isLineSafe(document.publicHost) {
            publicHost = document.publicHost
        }
        if document.publicPort >= 1, document.publicPort <= 65_535 {
            publicPort = document.publicPort
        }
        startAfterInstall = document.startAfterInstall
        startOnBoot = document.startOnBoot
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
    let cpuCount: Int
    let memoryGiB: Int
    let diskGiB: Int
    let networkMode: String
    let proxyPort: Int
    let vitalFilesDirectory: String
    let adminPassword: String
    let vmHostname: String
    let publicHost: String
    let publicPort: Int
    let startAfterInstall: Bool
    let startOnBoot: Bool
}
