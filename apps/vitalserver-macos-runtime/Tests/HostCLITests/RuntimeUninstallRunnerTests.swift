import Core
import Contracts
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeUninstallRunnerTests: XCTestCase {
    func testCleanUninstallStopsServicesBeforeRemovingInstalledFilesAndTools() throws {
        let harness = RuntimeUninstallRunnerHarness()

        try harness.runner.run(RuntimeUninstallCommand(clean: true))

        XCTAssertEqual(harness.events, [
            "log:uninstall started clean=true",
            "log:step=stop-launchd-services status=started",
            "stop",
            "log:step=stop-launchd-services status=completed",
            "log:step=remove-plists status=started",
            "remove:/Library/LaunchDaemons/com.tirosh.vitalserver-watchdog.plist",
            "remove:/Library/LaunchDaemons/com.tirosh.vitalserver-guest-log-sync.plist",
            "remove:/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist",
            "remove:/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist",
            "remove:/Library/LaunchDaemons/com.tirosh.vitalserver-sleep-prevention.plist",
            "log:step=remove-plists status=completed",
            "log:step=remove-installed-files status=started",
            "remove:/Applications/VitalServer Helper.app",
            "remove:/product",
            "remove:/external-vital-files",
            "log:step=remove-installed-files status=completed",
            "log:step=remove-runtime-tools status=started",
            "remove:/usr/local/bin/vitalserver-vm",
            "remove:/usr/local/bin/vitalserver-proxy-run",
            "remove:/usr/local/bin/tirosh-vitalserver-uninstall",
            "log:step=remove-runtime-tools status=completed",
            "log:step=forget-package-receipt status=started",
            "log:forget package receipt identifier=com.tirosh.vitalserver.vm",
            "forget:com.tirosh.vitalserver.vm",
            "log:forget package receipt identifier=com.tirosh.vitalserver",
            "forget:com.tirosh.vitalserver",
            "log:step=forget-package-receipt status=completed",
            "log:uninstall completed",
        ])
    }

    func testStandardUninstallCreatesBackupAndPreservesUserData() throws {
        let harness = RuntimeUninstallRunnerHarness(configuredVitalFilesDirectory: "/product/vm/data/vital-files")

        try harness.runner.run(RuntimeUninstallCommand(clean: false))

        XCTAssertEqual(harness.events.filter { $0 == "backup" }, ["backup"])
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/logs->") && $0.hasSuffix("/logs") })
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/backups->") && $0.hasSuffix("/backups") })
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/vm/data/backups/redis->") && $0.hasSuffix("/redis-backups") })
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/vm/data/vital-files->") && $0.hasSuffix("/vital-files") })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/vital-files->/product/vm/data/vital-files")
        })
        XCTAssertFalse(harness.events.contains("remove:/product/vm/data/vital-files"))
    }

    func testStandardUninstallStopsWhenBackupFails() {
        let harness = RuntimeUninstallRunnerHarness()
        harness.backupError = RuntimeUninstallTestError.backup

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertEqual(Array(harness.events.prefix(3)), [
            "log:uninstall started clean=false",
            "log:step=create-redis-backup status=started",
            "backup",
        ])
        XCTAssertTrue(harness.events.last?.hasPrefix(
            "log:standard uninstall aborted because Redis backup did not complete error="
        ) == true)
    }

    func testStandardUninstallRestoresPreservedDataWhenRemovalFails() {
        let harness = RuntimeUninstallRunnerHarness(configuredVitalFilesDirectory: "/product/vm/data/vital-files")
        harness.removeErrorPath = "/product"

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.events.contains("log:restoring preserved user data after uninstall failure"))
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/logs->/product/logs")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/vital-files->/product/vm/data/vital-files")
        })
    }
}

private final class RuntimeUninstallRunnerHarness {
    var events: [String] = []
    var existing: Set<String>
    var backupError: Error?
    var removeErrorPath: String?
    let configuredVitalFilesDirectory: String

    init(configuredVitalFilesDirectory: String = "/external-vital-files") {
        self.configuredVitalFilesDirectory = configuredVitalFilesDirectory
        self.existing = [
            "/product",
            "/product/logs",
            "/product/backups",
            "/product/vm/data/backups/redis",
            configuredVitalFilesDirectory,
            "/Applications/VitalServer Helper.app",
            "/Library/LaunchDaemons/com.tirosh.vitalserver-watchdog.plist",
            "/Library/LaunchDaemons/com.tirosh.vitalserver-guest-log-sync.plist",
            "/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist",
            "/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist",
            "/Library/LaunchDaemons/com.tirosh.vitalserver-sleep-prevention.plist",
            "/usr/local/bin/vitalserver-vm",
            "/usr/local/bin/vitalserver-proxy-run",
            "/usr/local/bin/tirosh-vitalserver-uninstall",
        ]
    }

    var runner: RuntimeUninstallRunner {
        RuntimeUninstallRunner(
            paths: RuntimeUninstallPaths(
                productRoot: URL(fileURLWithPath: "/product"),
                managerApp: URL(fileURLWithPath: "/Applications/VitalServer Helper.app"),
                defaultVitalFilesDirectory: URL(fileURLWithPath: "/product/vm/data/vital-files"),
                configuredVitalFilesDirectory: URL(fileURLWithPath: configuredVitalFilesDirectory),
                launchDaemonPlists: RuntimeManagedService.stopOrder.map {
                    URL(fileURLWithPath: "/Library/LaunchDaemons/\($0.label).plist")
                },
                runtimeTools: [
                    URL(fileURLWithPath: "/usr/local/bin/vitalserver-vm"),
                    URL(fileURLWithPath: "/usr/local/bin/vitalserver-proxy-run"),
                    URL(fileURLWithPath: "/usr/local/bin/tirosh-vitalserver-uninstall"),
                ]
            ),
            createRedisBackup: {
                self.events.append("backup")
                if let backupError = self.backupError {
                    throw backupError
                }
            },
            stopRuntimeServices: {
                self.events.append("stop")
            },
            fileExists: { url in
                self.existing.contains(url.path)
            },
            directoryExists: { url in
                self.existing.contains(url.path)
            },
            createDirectory: { url, _ in
                self.events.append("mkdir:\(url.path)")
                self.existing.insert(url.path)
            },
            removeItem: { url in
                self.events.append("remove:\(url.path)")
                if self.removeErrorPath == url.path {
                    throw RuntimeUninstallTestError.remove
                }
                self.existing.remove(url.path)
            },
            moveItem: { source, destination in
                self.events.append("move:\(source.path)->\(destination.path)")
                self.existing.remove(source.path)
                self.existing.insert(destination.path)
            },
            contentsOfDirectory: { _ in [] },
            runProcess: { _, _ in
                RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
            },
            packageReceiptIdentifiers: [
                "com.tirosh.vitalserver.vm",
                "com.tirosh.vitalserver",
            ],
            forgetPackageReceipt: { identifier in
                self.events.append("forget:\(identifier)")
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }
}

private enum RuntimeUninstallTestError: Error {
    case backup
    case remove
}
