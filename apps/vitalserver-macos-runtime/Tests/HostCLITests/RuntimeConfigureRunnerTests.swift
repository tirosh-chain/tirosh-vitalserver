import Foundation
import Core
import Contracts
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeConfigureRunnerTests: XCTestCase {
    func testConfigureUpdatesRuntimeDocumentsAndRunsRequestedActions() throws {
        let harness = try Harness()
        let cpuCount = Constants.Defaults.minimumCPUCount
        let memoryGiB = Constants.Defaults.maximumAllowedMemoryGiB

        let result = try harness.runner.configure(RuntimeConfigureCommand(
            changes: [
                .cpu(cpuCount),
                .memoryGiB(UInt64(memoryGiB)),
                .diskGiB(96),
                .network(.shared),
                .proxyPort(18080),
                .vitalFilesDirectory(URL(fileURLWithPath: "/data/vital-files")),
                .publicHost("vitalserver.local"),
                .publicPort(8080),
                .adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password")),
                .startOnBoot(false),
                .autoRecovery(false),
                .preventSystemSleep(false),
                .redisBackupRetention(20),
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
        XCTAssertEqual(guestConfig.publicHost, "vitalserver.local")
        XCTAssertEqual(guestConfig.publicPort, 8080)
        XCTAssertEqual(guestConfig.adminPassword, "secret")
        XCTAssertEqual(guestConfig.vitalFilesDirectory, Constants.Defaults.vitalFilesDirectoryGuestMountPath)
        XCTAssertEqual(guestConfig.redisBackupRetentionCount, 20)
        let settingsData = try XCTUnwrap(harness.fileStore.files[harness.paths.guestRuntimeSettings])
        let guestSettings = try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: settingsData)
        XCTAssertEqual(guestSettings.publicHost, "vitalserver.local")
        XCTAssertEqual(guestSettings.publicPort, 8080)
        XCTAssertEqual(guestSettings.redisBackupRetentionCount, 20)
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
            changes: [.redisBackupRetention(0)]
        ))) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "--redis-backup-retention must be between 1 and 30")
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
            fileStore.files[paths.guestRuntimeConfig] = try JSONEncoder().encode(GuestRuntimeConfigDocument.default)
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
                    restartRuntimeServices: { [weak self] in
                        self?.restartCount += 1
                    }
                ),
                log: { _ in }
            )
        }
    }
}
