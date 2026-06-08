import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeUninstallWorkflowTests: XCTestCase {
    func testCleanUninstallStopsServicesBeforeRemovingInstalledFilesAndTools() throws {
        let harness = RuntimeUninstallWorkflowHarness()

        try harness.run(RuntimeUninstallCommand(clean: true))

        XCTAssertEqual(harness.events, [
            "log:uninstall started clean=true",
            "state:started:uninstall started:",
            "log:step=stop-launchd-services status=started",
            "state:stop-services-requested:service stop requested:",
            "stop",
            "stop:clean=true",
            "log:step=stop-launchd-services status=completed",
            "state:files-removal-started:file removal started:",
            "log:step=remove-plists status=started",
            "remove:/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.watchdog.plist",
            "remove:/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.guest-log-sync.plist",
            "remove:/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.proxy.plist",
            "remove:/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.vm.plist",
            "remove:/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.sleep-prevention.plist",
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
            "state:receipts-forget-started:package receipt forget started:",
            "log:package receipt already absent identifier=ai.tirosh.vitalserver.helper",
            "log:step=clear-launchd-disabled-overrides status=started",
            "clear-disabled-overrides",
            "log:step=clear-launchd-disabled-overrides status=completed",
            "log:step=forget-package-receipt status=completed",
            "log:uninstall completed",
            "state:completed:uninstall completed:",
        ])
    }

    func testStandardUninstallCreatesBackupAndPreservesUserData() throws {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)

        try harness.run(RuntimeUninstallCommand(clean: false))

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

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

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

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

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

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("log:preserved user data restore failed error=")
        })
        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("file-removal-failed:reason=")
                && $0.contains("restore-preserved-user-data-failed:reason=")
        })
    }

    func testRemovalDiagnosticsLogsDirectoryReadFailure() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.removeErrorPath = "/product"
        harness.contentsOfDirectoryError = RuntimeUninstallTestError.diagnosticRead

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0 == "log:removal diagnostic contents read failed target=/product error=diagnostic read failed"
        })
    }

    func testUninstallDoesNotSkipRemovalWhenTargetPathInspectionFails() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.pathStates["/product"] = .inspectFailed("permission denied")

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true))) { error in
            XCTAssertTrue(error.localizedDescription.contains(
                "removal target path inspection failed target=/product reason=permission denied"
            ))
        }

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("removal target path inspection failed target=/product reason=permission denied")
        })
        XCTAssertFalse(harness.events.contains("remove:/product"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testUninstallDoesNotSkipRemovalWhenTargetPathStateIsUnknown() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.pathStates["/product"] = .unknown("socket")

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true))) { error in
            XCTAssertTrue(error.localizedDescription.contains(
                "removal target path state is unexpected target=/product state=socket"
            ))
        }

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("removal target path state is unexpected target=/product state=socket")
        })
        XCTAssertFalse(harness.events.contains("remove:/product"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testUninstallWritesServiceStopBlockedFromExplicitHostStates() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.stopError = RuntimeUninstallTestError.stop
        harness.serviceStates[.watchdog] = .readFailed("exitCode=1 stderr=denied")
        harness.vmProcessState = .running(pid: 123)

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("launchd-service-read-failed:label=\(RuntimeManagedService.watchdog.label)")
                && $0.contains("vm-process-running:pid=123")
        })
        XCTAssertFalse(harness.events.contains("log:uninstall completed"))
    }

    func testForceCleanUninstallBypassesServiceStopBlockingAndCompletes() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.stopError = RuntimeUninstallTestError.stop
        harness.vmProcessState = .running(pid: 123)

        try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("vm-process-running:pid=123")
        })
        XCTAssertTrue(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testCleanFlagIsPassedToRuntimeServiceStopEffect() throws {
        let cleanHarness = RuntimeUninstallWorkflowHarness()
        try cleanHarness.run(RuntimeUninstallCommand(clean: true))
        XCTAssertTrue(cleanHarness.events.contains("stop:clean=true"))

        let standardHarness = RuntimeUninstallWorkflowHarness()
        try standardHarness.run(RuntimeUninstallCommand(clean: false))
        XCTAssertTrue(standardHarness.events.contains("stop:clean=false"))
    }

    func testUninstallDoesNotRemoveFilesWhenStoppedStateIsNotProven() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.serviceStates[.vm] = .loaded
        harness.vmProcessState = .pidFileMissing

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("vm-process-pid-file-missing")
        })
        XCTAssertFalse(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testUninstallRemovesFilesWhenPidFileIsMissingAndVMServiceIsNotLoaded() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.vmProcessState = .pidFileMissing

        try harness.run(RuntimeUninstallCommand(clean: true))

        XCTAssertTrue(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertTrue(harness.events.contains("remove:/product"))
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testCleanUninstallDoesNotCompleteWhenCleanupArtifactRemains() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.cleanupArtifactStates = [
            .present(path: "/usr/local/bin/vitalserver-vm"),
        ]

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("runtime-artifact-present:path=/usr/local/bin/vitalserver-vm")
        })
        XCTAssertFalse(harness.events.contains("log:step=forget-package-receipt status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testForceCleanUninstallSkipsCleanupArtifactBlockerAndCompletes() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.cleanupArtifactStates = [
            .present(path: "/usr/local/bin/vitalserver-vm"),
        ]

        try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("runtime-artifact-present:path=/usr/local/bin/vitalserver-vm")
        })
        XCTAssertTrue(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testReceiptForgetFailureWritesBlockedState() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.receiptStates = [
            .present(identifier: "ai.tirosh.vitalserver.helper"),
        ]
        harness.receiptForgetResults["ai.tirosh.vitalserver.helper"] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "receipt locked"
        )

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:receipts-forget-blocked")
                && $0.contains("package-receipt-forget-failed:identifier=ai.tirosh.vitalserver.helper")
                && $0.contains("stderr=receipt locked")
        })
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testPresentReceiptIsForgottenBeforeCompletion() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.receiptStates = [
            .present(identifier: "ai.tirosh.vitalserver.helper"),
        ]

        try harness.run(RuntimeUninstallCommand(clean: true))

        XCTAssertTrue(harness.events.contains("log:forget package receipt identifier=ai.tirosh.vitalserver.helper"))
        XCTAssertTrue(harness.events.contains("forget:ai.tirosh.vitalserver.helper"))
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testReceiptRemainingAfterForgetWritesBlockedState() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.updateReceiptsOnForget = false
        harness.receiptStates = [
            .present(identifier: "ai.tirosh.vitalserver.helper"),
        ]

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:receipts-forget-blocked")
                && $0.contains("package-receipt-present:identifier=ai.tirosh.vitalserver.helper")
        })
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testForceCleanUninstallBypassesReceiptBlockingAndCompletes() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.updateReceiptsOnForget = false
        harness.receiptStates = [
            .present(identifier: "ai.tirosh.vitalserver.helper"),
        ]

        try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:receipts-forget-blocked")
                && $0.contains("package-receipt-present:identifier=ai.tirosh.vitalserver.helper")
        })
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testUninstallDoesNotCompleteWhenLaunchdDisabledOverrideCleanupFails() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.clearLaunchdDisabledOverridesError = RuntimeUninstallTestError.clearLaunchdDisabledOverrides

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains("log:step=clear-launchd-disabled-overrides status=started"))
        XCTAssertTrue(harness.events.contains("clear-disabled-overrides"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }
}

private final class RuntimeUninstallWorkflowHarness {
    var events: [String] = []
    var existing: Set<String>
    var backupError: Error?
    var stopError: Error?
    var clearLaunchdDisabledOverridesError: Error?
    var removeErrorPath: String?
    var moveErrorDestination: String?
    var contentsOfDirectoryError: Error?
    var pathStates: [String: RuntimePathState] = [:]
    var serviceStates: [RuntimeManagedService: RuntimeServiceState]
    var vmProcessState: RuntimeVMProcessState = .stopped
    var receiptForgetResults: [String: RuntimeProcessResult] = [:]
    var updateReceiptsOnForget = true
    var receiptStates: [RuntimePackageReceiptState] = [
        .absent(identifier: "ai.tirosh.vitalserver.helper"),
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
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.watchdog.plist",
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.guest-log-sync.plist",
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.proxy.plist",
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.vm.plist",
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.sleep-prevention.plist",
            "/usr/local/bin/vitalserver-vm",
            "/usr/local/bin/vitalserver-proxy-run",
            "/usr/local/bin/tirosh-vitalserver-uninstall",
        ]
        if let externalVitalFilesDirectory {
            self.existing.insert(externalVitalFilesDirectory)
        }
    }

    func run(_ command: RuntimeUninstallCommand) throws {
        try RuntimeUninstallWorkflow().run(
            command,
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
            readers: RuntimeUninstallStateReaders(
                serviceStates: {
                    self.serviceStates
                },
                vmProcessState: {
                    self.vmProcessState
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
                }
            ),
            effects: RuntimeUninstallEffects(
                createRedisBackup: {
                    self.events.append("backup")
                    if let backupError = self.backupError {
                        throw backupError
                    }
                },
                stopRuntimeServices: { clean in
                    self.events.append("stop")
                    self.events.append("stop:clean=\(clean)")
                    if let stopError = self.stopError {
                        throw stopError
                    }
                },
                clearLaunchdDisabledOverrides: {
                    self.events.append("clear-disabled-overrides")
                    if let clearLaunchdDisabledOverridesError = self.clearLaunchdDisabledOverridesError {
                        throw clearLaunchdDisabledOverridesError
                    }
                },
                describeError: { error in
                    error.localizedDescription
                },
                temporaryDirectory: {
                    URL(fileURLWithPath: NSTemporaryDirectory())
                },
                uniqueID: {
                    "test-preserve"
                },
                createDirectory: { url, _ in
                    self.createDirectory(url)
                },
                pathState: { url in
                    self.pathStates[url.path] ?? (self.existing.contains(url.path) ? .directory : .missing)
                },
                removeItem: { url in
                    try self.removeItem(url)
                },
                moveItem: { source, destination in
                    try self.moveItem(from: source, to: destination)
                },
                contentsOfDirectory: { _, _ in
                    if let contentsOfDirectoryError = self.contentsOfDirectoryError {
                        throw contentsOfDirectoryError
                    }
                    return []
                },
                openFilesInDirectory: { _ in
                    RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
                },
                forgetPackageReceipt: { identifier in
                    self.forgetPackageReceipt(identifier)
                }
            ),
            writer: RuntimeUninstallStateWriter(
                writeState: { state, _, message, blockers in
                    self.events.append("state:\(state.rawValue):\(message ?? ""):\(blockers.joined(separator: "|"))")
                }
            ),
            diagnostics: RuntimeUninstallDiagnostics(log: { message in
                self.events.append("log:\(message)")
            }),
            packageReceiptIdentifiers: [
                "ai.tirosh.vitalserver.helper",
            ]
        )
    }

    private func executeFileRemoval(
        paths: RuntimeUninstallPaths,
        clean: Bool
    ) throws {
        let useCase = UninstallRuntimeUseCase()
        var preserved: RuntimeUninstallPreservedPaths?
        do {
            events.append("log:\(useCase.stepLogMessage(step: .removePlists, status: .started))")
            for plist in paths.launchDaemonPlists {
                try removeIfPresent(plist, useCase: useCase)
            }
            events.append("log:\(useCase.stepLogMessage(step: .removePlists, status: .completed))")

            if !clean {
                preserved = try preserveUserData(paths: paths, useCase: useCase)
            }

            events.append("log:\(useCase.stepLogMessage(step: .removeInstalledFiles, status: .started))")
            let removalPlan = useCase.removalPlan(
                clean: clean,
                managerApp: paths.managerApp,
                productRoot: paths.productRoot,
                externalVitalFilesDirectory: paths.externalVitalFilesDirectory,
                configuredVitalFilesDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
            )
            for target in removalPlan.targets {
                try safeRemove(target, useCase: useCase)
            }
            if let skippedExternalDirectoryLogMessage = removalPlan.skippedExternalDirectoryLogMessage {
                events.append("log:\(skippedExternalDirectoryLogMessage)")
            }
            events.append("log:\(useCase.stepLogMessage(step: .removeInstalledFiles, status: .completed))")

            events.append("log:\(useCase.stepLogMessage(step: .removeRuntimeTools, status: .started))")
            for tool in paths.runtimeTools {
                try removeIfPresent(tool, useCase: useCase)
            }
            events.append("log:\(useCase.stepLogMessage(step: .removeRuntimeTools, status: .completed))")

            if let preserved {
                events.append("log:\(useCase.stepLogMessage(step: .restorePreservedUserData, status: .started))")
                try restorePreservedPaths(preserved, useCase: useCase)
                events.append("log:\(useCase.stepLogMessage(step: .restorePreservedUserData, status: .completed))")
            }
        } catch {
            var preservedRestoreFailureReason: String?
            if let preserved {
                events.append("log:\(useCase.restoringPreservedUserDataAfterFailureLogMessage())")
                do {
                    try restorePreservedPaths(preserved, useCase: useCase)
                } catch {
                    events.append("log:\(useCase.preservedUserDataRestoreFailedLogMessage(reason: error.localizedDescription))")
                    preservedRestoreFailureReason = error.localizedDescription
                }
            }
            throw RuntimeUninstallFileRemovalExecutionError(
                underlyingError: error,
                blockers: useCase.fileRemovalBlockers(
                    removalFailureReason: error.localizedDescription,
                    preservedRestoreFailureReason: preservedRestoreFailureReason
                )
            )
        }
    }

    private func preserveUserData(
        paths: RuntimeUninstallPaths,
        useCase: UninstallRuntimeUseCase
    ) throws -> RuntimeUninstallPreservedPaths {
        events.append("log:\(useCase.stepLogMessage(step: .preserveUserData, status: .started))")
        let preserveRoot = useCase.preserveRootDirectory(
            temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            uniqueID: UUID().uuidString
        )
        createDirectory(preserveRoot)

        var items: [RuntimeUninstallPreservedPath] = []
        let plan = useCase.preservePlan(
            productRoot: paths.productRoot,
            defaultVitalFilesDirectory: paths.defaultVitalFilesDirectory,
            externalVitalFilesDirectory: paths.externalVitalFilesDirectory,
            configuredVitalFilesDirectoryReadFailure: paths.configuredVitalFilesDirectoryReadFailure
        )
        for candidate in plan.candidates {
            guard existing.contains(candidate.source.path) else {
                continue
            }
            let destination = preserveRoot.appendingPathComponent(candidate.token)
            try removeIfPresent(destination, useCase: useCase)
            try moveItem(from: candidate.source, to: destination)
            items.append(RuntimeUninstallPreservedPath(source: candidate.source, destination: destination))
            events.append("log:\(useCase.preservedSourceLogMessage(path: candidate.source.path))")
        }
        if let externalDirectoryLogMessage = plan.externalDirectoryLogMessage {
            events.append("log:\(externalDirectoryLogMessage)")
        }
        if let configuredDirectoryReadFailureLogMessage = plan.configuredDirectoryReadFailureLogMessage {
            events.append("log:\(configuredDirectoryReadFailureLogMessage)")
        }
        events.append("log:\(useCase.stepLogMessage(step: .preserveUserData, status: .completed))")
        return RuntimeUninstallPreservedPaths(root: preserveRoot, items: items)
    }

    private func restorePreservedPaths(
        _ preserved: RuntimeUninstallPreservedPaths,
        useCase: UninstallRuntimeUseCase
    ) throws {
        for item in preserved.items {
            createDirectory(item.source.deletingLastPathComponent())
            try removeIfPresent(item.source, useCase: useCase)
            try moveItem(from: item.destination, to: item.source)
            events.append("log:\(useCase.restoredPreservedLogMessage(path: item.source.path))")
        }
        try removeIfPresent(preserved.root, useCase: useCase)
    }

    private func safeRemove(_ target: URL, useCase: UninstallRuntimeUseCase) throws {
        guard target.path != "/" else {
            throw UninstallRuntimeUseCaseError.operationFailed(
                useCase.unsafeRemovalTargetFailureMessage(path: target.path)
            )
        }
        guard existing.contains(target.path) else {
            return
        }
        do {
            try removeItem(target)
        } catch {
            logRemovalDiagnostics(target, useCase: useCase)
            throw error
        }
        if existing.contains(target.path) {
            logRemovalDiagnostics(target, useCase: useCase)
            throw UninstallRuntimeUseCaseError.operationFailed(
                useCase.removalIncompleteFailureMessage(path: target.path)
            )
        }
    }

    private func logRemovalDiagnostics(_ target: URL, useCase: UninstallRuntimeUseCase) {
        events.append("log:\(useCase.removalDiagnosticTargetLogMessage(path: target.path))")
        if let contentsOfDirectoryError {
            let message = useCase.removalDiagnosticContentsReadFailedLogMessage(
                path: target.path,
                reason: contentsOfDirectoryError.localizedDescription
            )
            events.append("log:\(message)")
        }
    }

    private func removeIfPresent(_ url: URL, useCase: UninstallRuntimeUseCase) throws {
        guard existing.contains(url.path) else {
            return
        }
        try removeItem(url)
    }

    private func createDirectory(_ url: URL) {
        events.append("mkdir:\(url.path)")
        existing.insert(url.path)
    }

    private func removeItem(_ url: URL) throws {
        events.append("remove:\(url.path)")
        if removeErrorPath == url.path {
            throw RuntimeUninstallTestError.remove
        }
        existing.remove(url.path)
    }

    private func moveItem(from source: URL, to destination: URL) throws {
        events.append("move:\(source.path)->\(destination.path)")
        if destination.path == moveErrorDestination {
            throw RuntimeUninstallTestError.restore
        }
        existing.remove(source.path)
        existing.insert(destination.path)
    }

    private func forgetPackageReceipt(_ identifier: String) -> RuntimeProcessResult {
        events.append("forget:\(identifier)")
        let result = receiptForgetResults[identifier] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
        if result.exitCode == 0 && updateReceiptsOnForget {
            receiptStates = receiptStates.map { state in
                switch state {
                case .present(let existingIdentifier) where existingIdentifier == identifier:
                    return .absent(identifier: identifier)
                default:
                    return state
                }
            }
        }
        return result
    }

    private func executeReceiptForgetting(
        identifiers: [String],
        observedReceiptStates: [String: RuntimePackageReceiptState]
    ) throws {
        let useCase = UninstallRuntimeUseCase()
        for identifier in identifiers {
            switch useCase.receiptForgetDecision(identifier: identifier, observedReceiptStates: observedReceiptStates) {
            case .skip(let logMessage):
                events.append("log:\(logMessage)")
                continue
            case .forget(let logMessage):
                events.append("log:\(logMessage)")
            }
            events.append("forget:\(identifier)")
            let result = receiptForgetResults[identifier] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            if result.exitCode == 0 && updateReceiptsOnForget {
                receiptStates = receiptStates.map { state in
                    switch state {
                    case .present(let existingIdentifier) where existingIdentifier == identifier:
                        return .absent(identifier: identifier)
                    default:
                        return state
                    }
                }
            }
            guard result.exitCode == 0 else {
                throw RuntimeUninstallReceiptForgetExecutionError(
                    identifier: identifier,
                    reason: useCase.processFailureReason(result)
                )
            }
        }
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

private struct RuntimeUninstallPreservedPaths {
    let root: URL
    let items: [RuntimeUninstallPreservedPath]
}

private struct RuntimeUninstallPreservedPath {
    let source: URL
    let destination: URL
}

private enum RuntimeUninstallTestError: Error, LocalizedError {
    case backup
    case remove
    case stop
    case clearLaunchdDisabledOverrides
    case restore
    case diagnosticRead

    var errorDescription: String? {
        switch self {
        case .backup:
            return "backup failed"
        case .remove:
            return "remove failed"
        case .stop:
            return "stop failed"
        case .clearLaunchdDisabledOverrides:
            return "clear launchd disabled overrides failed"
        case .restore:
            return "restore failed"
        case .diagnosticRead:
            return "diagnostic read failed"
        }
    }
}
