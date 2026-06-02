import Core
import Contracts
import RuntimeWorkflow
import XCTest

final class RuntimeUninstallWorkflowTests: XCTestCase {
    func testCleanUninstallStopsServicesBeforeRemovingInstalledFilesAndTools() throws {
        let harness = RuntimeUninstallWorkflowHarness()

        try harness.runner.run(RuntimeUninstallCommand(clean: true))

        XCTAssertEqual(harness.events, [
            "log:uninstall started clean=true",
            "state:started:uninstall started:",
            "log:step=stop-launchd-services status=started",
            "state:stop-services-requested:service stop requested:",
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
            "state:files-removal-started:file removal started:",
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
            "state:receipts-forget-started:package receipt forget started:",
            "log:forget package receipt identifier=com.tirosh.vitalserver.vm",
            "forget:com.tirosh.vitalserver.vm",
            "log:forget package receipt identifier=com.tirosh.vitalserver",
            "forget:com.tirosh.vitalserver",
            "log:step=forget-package-receipt status=completed",
            "log:uninstall completed",
            "state:completed:uninstall completed:",
        ])
    }

    func testStandardUninstallCreatesBackupAndPreservesUserData() throws {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)

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
        let harness = RuntimeUninstallWorkflowHarness()
        harness.backupError = RuntimeUninstallTestError.backup

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertEqual(Array(harness.events.prefix(5)), [
            "log:uninstall started clean=false",
            "state:started:uninstall started:",
            "log:step=create-redis-backup status=started",
            "state:redis-backup-requested:redis backup requested:",
            "backup",
        ])
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("log:standard uninstall aborted because Redis backup did not complete error=")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("state:failed:redis backup failed:redis-backup-failed:reason=")
        })
    }

    func testStandardUninstallRestoresPreservedDataWhenRemovalFails() {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)
        harness.removeErrorPath = "/product"

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.events.contains("log:restoring preserved user data after uninstall failure"))
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/logs->/product/logs")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/vital-files->/product/vm/data/vital-files")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("state:files-removal-blocked:file removal blocked:file-removal-failed:reason=")
        })
    }

    func testStandardUninstallReportsPreservedDataRestoreFailure() {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)
        harness.removeErrorPath = "/product"
        harness.moveErrorDestination = "/product/vm/data/vital-files"

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("log:preserved user data restore failed error=")
        })
        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("file-removal-failed:reason=")
                && $0.contains("restore-preserved-user-data-failed:reason=")
        })
    }

    func testUninstallWritesServiceStopBlockedFromExplicitHostStates() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.stopError = RuntimeUninstallTestError.stop
        harness.serviceStates[.watchdog] = .readFailed("exitCode=1 stderr=denied")
        harness.vmProcessState = .running(pid: 123)

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("launchd-service-read-failed:label=\(RuntimeManagedService.watchdog.label)")
                && $0.contains("vm-process-running:pid=123")
        })
        XCTAssertFalse(harness.events.contains("log:uninstall completed"))
    }

    func testUninstallDoesNotRemoveFilesWhenStoppedStateIsNotProven() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.vmProcessState = .pidFileMissing

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("vm-process-pid-file-missing")
        })
        XCTAssertFalse(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testCleanUninstallDoesNotCompleteWhenCleanupArtifactRemains() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.cleanupArtifactStates = [
            .present(path: "/usr/local/bin/vitalserver-vm"),
        ]

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("runtime-artifact-present:path=/usr/local/bin/vitalserver-vm")
        })
        XCTAssertFalse(harness.events.contains("log:step=forget-package-receipt status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testReceiptForgetFailureWritesBlockedState() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.receiptForgetResults["com.tirosh.vitalserver.vm"] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "receipt locked"
        )

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:receipts-forget-blocked")
                && $0.contains("package-receipt-forget-failed:identifier=com.tirosh.vitalserver.vm")
                && $0.contains("stderr=receipt locked")
        })
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testReceiptRemainingAfterForgetWritesBlockedState() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.receiptStates = [
            .present(identifier: "com.tirosh.vitalserver.vm"),
            .absent(identifier: "com.tirosh.vitalserver"),
        ]

        XCTAssertThrowsError(try harness.runner.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:receipts-forget-blocked")
                && $0.contains("package-receipt-present:identifier=com.tirosh.vitalserver.vm")
        })
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }
}

private final class RuntimeUninstallWorkflowHarness {
    var events: [String] = []
    var existing: Set<String>
    var backupError: Error?
    var stopError: Error?
    var removeErrorPath: String?
    var moveErrorDestination: String?
    var serviceStates: [RuntimeManagedService: RuntimeServiceState]
    var vmProcessState: RuntimeVMProcessState = .stopped
    var receiptForgetResults: [String: RuntimeProcessResult] = [:]
    var receiptStates: [RuntimePackageReceiptState] = [
        .absent(identifier: "com.tirosh.vitalserver.vm"),
        .absent(identifier: "com.tirosh.vitalserver"),
    ]
    var cleanupArtifactStates: [RuntimeInstallArtifactState]?
    let externalVitalFilesDirectory: String?
    let configuredVitalFilesDirectoryReadFailure: String?

    init(
        externalVitalFilesDirectory: String? = "/external-vital-files",
        configuredVitalFilesDirectoryReadFailure: String? = nil
    ) {
        self.externalVitalFilesDirectory = externalVitalFilesDirectory
        self.configuredVitalFilesDirectoryReadFailure = configuredVitalFilesDirectoryReadFailure
        self.serviceStates = Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map {
            ($0, RuntimeServiceState.notLoaded)
        })
        self.existing = [
            "/product",
            "/product/logs",
            "/product/backups",
            "/product/vm/data/backups/redis",
            "/product/vm/data/vital-files",
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
        if let externalVitalFilesDirectory {
            self.existing.insert(externalVitalFilesDirectory)
        }
    }

    var runner: RuntimeUninstallWorkflow {
        RuntimeUninstallWorkflow(
            paths: RuntimeUninstallPaths(
                productRoot: URL(fileURLWithPath: "/product"),
                managerApp: URL(fileURLWithPath: "/Applications/VitalServer Helper.app"),
                defaultVitalFilesDirectory: URL(fileURLWithPath: "/product/vm/data/vital-files"),
                externalVitalFilesDirectory: externalVitalFilesDirectory.map(URL.init(fileURLWithPath:)),
                configuredVitalFilesDirectoryReadFailure: configuredVitalFilesDirectoryReadFailure,
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
                if let stopError = self.stopError {
                    throw stopError
                }
            },
            serviceStates: {
                self.serviceStates
            },
            vmProcessState: {
                self.vmProcessState
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
                if destination.path == self.moveErrorDestination {
                    throw RuntimeUninstallTestError.restore
                }
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
                return self.receiptForgetResults[identifier] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            packageReceiptStates: {
                self.receiptStates
            },
            cleanupArtifactStates: { clean in
                if let cleanupArtifactStates = self.cleanupArtifactStates {
                    return cleanupArtifactStates
                }
                return self.cleanupArtifactPaths(clean: clean).map { path in
                    self.existing.contains(path) ? .present(path: path) : .absent(path: path)
                }
            },
            writeState: { state, _, message, blockers in
                self.events.append("state:\(state.rawValue):\(message ?? ""):\(blockers.joined(separator: "|"))")
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }

    private func cleanupArtifactPaths(clean: Bool) -> [String] {
        var paths = [
            "/Applications/VitalServer Helper.app",
            "/Library/LaunchDaemons/\(RuntimeManagedService.watchdog.label).plist",
            "/Library/LaunchDaemons/\(RuntimeManagedService.guestLogSync.label).plist",
            "/Library/LaunchDaemons/\(RuntimeManagedService.proxy.label).plist",
            "/Library/LaunchDaemons/\(RuntimeManagedService.vm.label).plist",
            "/Library/LaunchDaemons/\(RuntimeManagedService.sleepPrevention.label).plist",
            "/usr/local/bin/vitalserver-vm",
            "/usr/local/bin/vitalserver-proxy-run",
            "/usr/local/bin/tirosh-vitalserver-uninstall",
        ]
        if clean {
            paths.append("/product")
            if let externalVitalFilesDirectory {
                paths.append(externalVitalFilesDirectory)
            }
        }
        return paths
    }
}

private enum RuntimeUninstallTestError: Error {
    case backup
    case remove
    case stop
    case restore
}
