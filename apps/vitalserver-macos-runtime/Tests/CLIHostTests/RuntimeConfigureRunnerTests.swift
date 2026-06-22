import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeConfigureRunnerTests: XCTestCase {
    func testConfigureUpdatesRuntimeDocumentsAndRunsRequestedActions() throws {
        let harness = try Harness()
        let cpuCount = Constants.Defaults.minimumCPUCount
        let memoryGiB = Constants.Defaults.maximumAllowedMemoryGiB(physicalMemoryBytes: 16 * 1_073_741_824)

        let result = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [
                .cpu(cpuCount),
                .memoryGiB(UInt64(memoryGiB)),
                .diskGiB(96),
                .network(.shared),
                .proxyPort(18080),
                .vitalFilesDirectory(URL(fileURLWithPath: "/data/vital-files")),
                .publicHost("stale.example"),
                .publicPort(8080),
                .vitalServerURL("https://vitaldb.tirosh.ai/"),
                .remoteConsoleURL("https://console.tirosh.ai/"),
                .adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password")),
                .startOnBoot(false),
                .autoRecovery(false),
                .preventSystemSleep(false),
                .backupRetention(20),
            ],
            restart: true
        ))

        XCTAssertTrue(result.restart)
        XCTAssertEqual(harness.resizedDisks, [96])
        XCTAssertEqual(harness.proxyPorts, [18080])
        XCTAssertEqual(harness.startOnBootValues, [false])
        XCTAssertEqual(harness.systemSleepPreventionValues, [false])
        XCTAssertEqual(harness.restrictedFiles, [harness.paths.guestRuntimeConfig])
        XCTAssertEqual(harness.restartCount, 1)
        XCTAssertTrue(harness.fileStore.directories.contains(URL(fileURLWithPath: "/data/vital-files")))

        let vmConfig = try VMRuntimeConfig.load(from: harness.vmConfigURL, fileStore: harness.fileStore)
        XCTAssertEqual(vmConfig.cpuCount, cpuCount)
        XCTAssertEqual(vmConfig.memoryMiB, UInt64(memoryGiB * 1024))
        XCTAssertEqual(vmConfig.network.mode, .shared)
        XCTAssertNil(vmConfig.network.bridgedInterface)
        XCTAssertEqual(vmConfig.vitalFilesDirectory?.hostPath, "/data/vital-files")
        XCTAssertEqual(vmConfig.autoRecoveryEnabled, false)
        XCTAssertEqual(vmConfig.preventSystemSleep, false)

        let guestConfig = try GuestRuntimeConfigDocument.load(from: harness.paths.guestRuntimeConfig, fileStore: harness.fileStore)
        XCTAssertEqual(guestConfig.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(guestConfig.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(guestConfig.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(guestConfig.publicPort, 443)
        XCTAssertEqual(guestConfig.adminPassword, "secret")
        XCTAssertEqual(guestConfig.vitalFilesDirectory, Constants.Defaults.vitalFilesDirectoryGuestMountPath)
        let settingsData = try XCTUnwrap(harness.fileStore.files[harness.paths.guestRuntimeSettings])
        let guestSettings = try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: settingsData)
        XCTAssertEqual(guestSettings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(guestSettings.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(guestSettings.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(guestSettings.publicPort, 443)
        XCTAssertEqual(guestSettings.backupRetentionCount, 20)
    }

    func testConfigureWritesLogArchiveSettingsWithoutRestartRequirement() throws {
        let harness = try Harness()
        harness.fileStore.files[harness.paths.runtimeControlSettings] = try JSONEncoder().encode(
            RuntimeControlSettingsDocument(logArchiveRetentionDays: 9, logArchiveMaximumGiB: 2)
        )

        let result = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [
                .logArchiveRetentionDays(21),
                .logArchiveMaximumGiB(4),
            ],
            restart: true
        ))

        XCTAssertFalse(result.restart)
        XCTAssertEqual(result.restartRequirement, .none)
        let data = try XCTUnwrap(harness.fileStore.files[harness.paths.runtimeControlSettings])
        let settings = try JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: data)
        XCTAssertEqual(settings, RuntimeControlSettingsDocument(logArchiveRetentionDays: 21, logArchiveMaximumGiB: 4))
    }

    func testConfigureMergesSingleLogArchiveSettingChangeWithExistingDocument() throws {
        let harness = try Harness()
        harness.fileStore.files[harness.paths.runtimeControlSettings] = try JSONEncoder().encode(
            RuntimeControlSettingsDocument(logArchiveRetentionDays: 9, logArchiveMaximumGiB: 2)
        )

        _ = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.logArchiveRetentionDays(12)]
        ))

        let data = try XCTUnwrap(harness.fileStore.files[harness.paths.runtimeControlSettings])
        let settings = try JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: data)
        XCTAssertEqual(settings, RuntimeControlSettingsDocument(logArchiveRetentionDays: 12, logArchiveMaximumGiB: 2))
    }

    func testConfigureWritesRedisRelayConfigAndSecretWithoutExposingPasswordInReadSettings() throws {
        let harness = try Harness()
        let relaySettingsFile = URL(fileURLWithPath: "/tmp/redis-relay-settings.json")
        harness.fileStore.files[relaySettingsFile] = Data("""
        {
          "enabled": true,
          "target": {
            "url": "redis://redis-hub.internal:6380/2",
            "username": "relay",
            "password": "secret-password",
            "clearPassword": false,
            "passwordConfigured": false,
            "tls": true
          },
          "scope": "vital_reconstruction",
          "includeRecorderNetworkContext": true,
          "intervalSeconds": 0.5,
          "scanCount": 500
        }
        """.utf8)

        let result = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.redisRelaySettingsFile(relaySettingsFile)]
        ))

        XCTAssertFalse(result.restart)
        XCTAssertTrue(harness.fileStore.directories.contains(harness.paths.redisRelayConfigDirectory))
        XCTAssertTrue(harness.fileStore.directories.contains(harness.paths.redisRelaySecretsDirectory))
        XCTAssertTrue(harness.fileStore.directories.contains(harness.paths.redisRelayStatusDirectory))
        XCTAssertEqual(
            String(data: try XCTUnwrap(harness.fileStore.files[harness.paths.redisRelayTargetPassword]), encoding: .utf8),
            "secret-password"
        )
        let toml = String(
            data: try XCTUnwrap(harness.fileStore.files[harness.paths.redisRelayConfig]),
            encoding: .utf8
        )
        XCTAssertTrue(toml?.contains("enabled = true") == true)
        XCTAssertTrue(toml?.contains("url = \"rediss://relay@redis-hub.internal:6380/2\"") == true)
        XCTAssertTrue(toml?.contains("password_file = \"/run/tirosh/secrets/redis-relay-target-password\"") == true)
        XCTAssertTrue(toml?.contains("[publish]") == true)
        XCTAssertTrue(toml?.contains("event_stream_key = \"vitalserver:relay:events\"") == true)

        let data = try XCTUnwrap(harness.fileStore.files[harness.paths.runtimeControlSettings])
        let settings = try JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: data)
        XCTAssertTrue(settings.redisRelay.enabled)
        XCTAssertEqual(settings.redisRelay.target.url, "redis://redis-hub.internal:6380/2")
        XCTAssertEqual(settings.redisRelay.target.username, "relay")
        XCTAssertTrue(settings.redisRelay.target.tls)
        XCTAssertTrue(settings.redisRelay.target.passwordConfigured)
        XCTAssertEqual(settings.redisRelay.target.password, "")
    }

    func testConfigureReconcilesGuestComposeForRedisRelayChangeWhenRestartIsRequested() throws {
        let harness = try Harness()
        let relaySettingsFile = URL(fileURLWithPath: "/tmp/redis-relay-settings.json")
        harness.fileStore.files[relaySettingsFile] = Data("""
        {
          "enabled": true,
          "target": {
            "url": "redis://redis-hub.internal:6380/2"
          },
          "scope": "vital_reconstruction",
          "includeRecorderNetworkContext": false,
          "intervalSeconds": 1.0,
          "scanCount": 1000
        }
        """.utf8)

        let result = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.redisRelaySettingsFile(relaySettingsFile)],
            restart: true
        ))

        XCTAssertTrue(result.restart)
        XCTAssertEqual(result.restartRequirement, .containerServices)
        XCTAssertEqual(harness.reconcileComposeCount, 1)
        XCTAssertEqual(harness.restartCount, 0)
    }

    func testConfigureRejectsInvalidLogArchiveSettings() throws {
        let harness = try Harness()

        XCTAssertThrowsError(try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.logArchiveRetentionDays(31)]
        ))) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "--log-archive-retention-days must be between 1 and 30")
        }

        XCTAssertThrowsError(try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.logArchiveMaximumGiB(21)]
        ))) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "--log-archive-maximum-gib must be between 1 and 20")
        }
    }

    func testConfigureWithoutRestartDoesNotRestartServices() throws {
        let harness = try Harness()

        let result = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.autoRecovery(false)]
        ))

        XCTAssertFalse(result.restart)
        XCTAssertEqual(harness.restartCount, 0)
        let vmConfig = try VMRuntimeConfig.load(from: harness.vmConfigURL, fileStore: harness.fileStore)
        XCTAssertEqual(vmConfig.autoRecoveryEnabled, false)
    }

    func testConfigureRejectsBridgedModeWithoutInterface() throws {
        let harness = try Harness()

        XCTAssertThrowsError(try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.network(.bridged)]
        ))) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "--bridged-interface is required when --network bridged")
        }
    }

    func testConfigureRejectsInvalidRedisBackupRetention() throws {
        let harness = try Harness()

        XCTAssertThrowsError(try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.backupRetention(0)]
        ))) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "--backup-retention must be between 1 and 30")
        }
    }

    func testConfigureRejectsEmptyAdvertisedURL() throws {
        let harness = try Harness()

        XCTAssertThrowsError(try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.vitalServerURL("")]
        ))) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "--vitalserver-url must be an absolute http/https URL")
        }
    }

    func testHTTPVitalServerURLWithoutExplicitPortResetsPublicPortToDefault() throws {
        let harness = try Harness()

        _ = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [
                .publicPort(8080),
                .vitalServerURL("http://vitaldb.tirosh.ai/"),
            ]
        ))

        let guestConfig = try GuestRuntimeConfigDocument.load(from: harness.paths.guestRuntimeConfig, fileStore: harness.fileStore)
        XCTAssertEqual(guestConfig.vitalServerURL, "http://vitaldb.tirosh.ai/")
        XCTAssertEqual(guestConfig.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(guestConfig.publicPort, Constants.Guest.publicPort)
    }

    func testConfigureFailsWhenGuestRuntimeConfigIsMissing() throws {
        let harness = try Harness()
        harness.fileStore.files[harness.paths.guestRuntimeConfig] = nil

        XCTAssertThrowsError(try harness.runner.configure(RuntimeConfigureCommand(
            changes: [.autoRecovery(false)]
        ))) { error in
            guard case LauncherError.missingFile(let path) = error else {
                return XCTFail("expected missingFile, got \(error)")
            }
            XCTAssertEqual(path, harness.paths.guestRuntimeConfig.path)
        }
    }

    final class Harness {
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        let vmConfigURL: URL
        var resizedDisks: [Int] = []
        var proxyPorts: [Int] = []
        var restrictedFiles: [URL] = []
        var startOnBootValues: [Bool] = []
        var systemSleepPreventionValues: [Bool] = []
        var automaticBackupSchedules: [(enabled: Bool, scheduleTimes: [String])] = []
        var reconcileComposeCount = 0
        var restartCount = 0
        var runner: RuntimeConfigureRunner!

        init() throws {
            vmConfigURL = paths.vmConfig
            let vmConfig = VMRuntimeConfig(
                cpuCount: 4,
                memoryMiB: 4096,
                kernelPath: "/runtime/kernel",
                initialRamdiskPath: "/runtime/initrd",
                diskPath: "/runtime/disk.img",
                cloudInitPath: nil,
                kernelCommandLine: "console=hvc0",
                network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: "02:00:00:00:00:01"),
                sharedDirectory: nil,
                vitalFilesDirectory: nil
            )
            fileStore.files[vmConfigURL] = try JSONEncoder().encode(vmConfig)
            fileStore.files[paths.vmDisk] = Data([0])
            let guestConfig = Self.defaultGuestRuntimeConfig()
            fileStore.files[paths.guestRuntimeConfig] = try JSONEncoder().encode(guestConfig)
            fileStore.files[paths.guestRuntimeSettings] = try JSONEncoder().encode(
                GuestRuntimeSettingsDocument(runtimeConfig: guestConfig)
            )
            fileStore.files[URL(fileURLWithPath: "/tmp/admin-password")] = Data("secret".utf8)

            runner = RuntimeConfigureRunner(
                installedPaths: paths,
                configURL: vmConfigURL,
                fileStore: fileStore,
                actions: RuntimeConfigureActions(
                    resizeVMDiskIfNeeded: { [weak self] diskGiB in
                        self?.resizedDisks.append(diskGiB)
                    },
                    setInstalledProxyPort: { [weak self] port in
                        self?.proxyPorts.append(port)
                    },
                    readSecretFile: { url in
                        guard let data = self.fileStore.files[url],
                              let value = String(data: data, encoding: .utf8) else {
                            throw LauncherError.missingFile(url.path)
                        }
                        return value
                    },
                    restrictSecretFile: { [weak self] url in
                        self?.restrictedFiles.append(url)
                    },
                    setStartOnBoot: { [weak self] enabled in
                        self?.startOnBootValues.append(enabled)
                    },
                    setSystemSleepPrevention: { [weak self] enabled in
                        self?.systemSleepPreventionValues.append(enabled)
                    },
                    setAutomaticBackupSchedule: { [weak self] enabled, scheduleTimes in
                        self?.automaticBackupSchedules.append((enabled: enabled, scheduleTimes: scheduleTimes))
                    },
                    reconcileGuestComposeServices: { [weak self] in
                        self?.reconcileComposeCount += 1
                    },
                    restartRuntimeServices: { [weak self] in
                        self?.restartCount += 1
                    }
                ),
                maximumAllowedCPUCount: Constants.Defaults.maximumAllowedCPUCount(systemCPUCount: 8),
                maximumAllowedMemoryGiB: Constants.Defaults.maximumAllowedMemoryGiB(
                    physicalMemoryBytes: 16 * 1_073_741_824
                ),
                log: { _ in }
            )
        }

        private static func defaultGuestRuntimeConfig() -> GuestRuntimeConfigDocument {
            GuestRuntimeConfigDocument(
                vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
                redisHost: Constants.Guest.redisHost,
                redisPort: Constants.Guest.redisPort,
                trustProxy: true,
                vitalServerURL: "",
                remoteConsoleURL: "",
                publicHost: "",
                publicPort: Constants.Guest.publicPort,
                adminPassword: Constants.Guest.defaultAdminPassword,
                vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                redisUiPort: Constants.Guest.redisUIPort,
                swaggerUiPort: Constants.Guest.swaggerUIPort,
                testkitEnabled: Constants.testkitContainerIncluded
            )
        }
    }
}
