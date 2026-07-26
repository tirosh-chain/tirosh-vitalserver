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
            "log:uninstall started clean=true forceClean=false",
            "state:started:uninstall started:",
            "log:configured Vital files ownership loaded revision=1 appliedRevision=none paths=/external-vital-files[desired:revision=1]",
            "log:step=stop-launchd-services status=started",
            "state:stop-services-requested:service stop requested:",
            "stop",
            "stop:clean=true",
            "stop:forceClean=false",
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
            "move:/product->/.product.uninstall-test-preserve",
            "state-store-relocated:/product->/.product.uninstall-test-preserve",
            "log:relocated product root source=/product destination=/.product.uninstall-test-preserve",
            "remove:/Applications/VitalServer Helper.app",
            "remove:/default-vital-files",
            "log:preserved configured external vital files directory path=/external-vital-files reason=no-product-owned-removal-contract",
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
            "log:step=dispose-uninstall-state-store status=started",
            "remove:/.product.uninstall-test-preserve",
            "log:step=dispose-uninstall-state-store status=completed",
        ])
        XCTAssertTrue(harness.existing.contains("/external-vital-files"))
    }

    func testCleanUninstallRemovesProductOwnedRetainedArchivesButPreservesExternalVitalFiles() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.existing.insert("/retained-uninstall-data")

        try harness.run(RuntimeUninstallCommand(clean: true))

        XCTAssertFalse(harness.existing.contains("/retained-uninstall-data"))
        XCTAssertTrue(harness.events.contains("remove:/retained-uninstall-data"))
        XCTAssertTrue(harness.existing.contains("/external-vital-files"))
        XCTAssertFalse(harness.events.contains("remove:/external-vital-files"))
    }

    func testStandardUninstallCreatesBackupAndPreservesUserData() throws {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)

        try harness.run(RuntimeUninstallCommand(clean: false))

        XCTAssertEqual(harness.events.filter { $0 == "backup" }, ["backup"])
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/logs->") && $0.hasSuffix("/logs") })
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/backups->") && $0.hasSuffix("/backups") })
        XCTAssertTrue(harness.events.contains { $0.hasPrefix("move:/product/vm/data/backups/redis->") && $0.hasSuffix("/redis-backups") })
        XCTAssertFalse(harness.events.contains {
            $0.hasPrefix("move:/default-vital-files->")
        })
        XCTAssertFalse(harness.existing.contains("/product"))
        XCTAssertTrue(harness.existing.contains("/default-vital-files"))
        XCTAssertTrue(harness.existing.contains(
            "/retained-uninstall-data/tirosh-vitalserver-uninstall-test-preserve"
        ))
        XCTAssertFalse(harness.events.contains("remove:/product/vm/data/vital-files"))
    }

    func testStandardUninstallRetainsConfiguredLegacyManagedDefaultVitalFiles() throws {
        let legacyDefault = "/product/vm/data/vital-files"
        let harness = RuntimeUninstallWorkflowHarness(
            externalVitalFilesDirectory: legacyDefault
        )

        try harness.run(RuntimeUninstallCommand(clean: false))

        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:\(legacyDefault)->")
                && $0.hasSuffix("/legacy-vital-files")
        })
        XCTAssertTrue(harness.existing.contains(
            "/retained-uninstall-data/tirosh-vitalserver-uninstall-test-preserve/legacy-vital-files"
        ))
        XCTAssertFalse(harness.existing.contains(legacyDefault))
    }

    func testStandardUninstallRetainsKnownLegacyManagedDefaultWhenConfiguredPathIsExternal() throws {
        let legacyDefault = "/product/vm/data/vital-files"
        let harness = RuntimeUninstallWorkflowHarness()
        harness.existing.insert(legacyDefault)

        try harness.run(RuntimeUninstallCommand(clean: false))

        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:\(legacyDefault)->")
                && $0.hasSuffix("/legacy-vital-files")
        })
        XCTAssertTrue(harness.existing.contains(
            "/retained-uninstall-data/tirosh-vitalserver-uninstall-test-preserve/legacy-vital-files"
        ))
        XCTAssertFalse(harness.existing.contains(legacyDefault))
        XCTAssertTrue(harness.existing.contains("/external-vital-files"))
    }

    func testStandardUninstallStopsWhenBackupFails() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.backupError = RuntimeUninstallTestError.backup

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertEqual(Array(harness.events.prefix(6)), [
            "log:uninstall started clean=false forceClean=false",
            "state:started:uninstall started:",
            "log:configured Vital files ownership loaded revision=1 appliedRevision=none paths=/external-vital-files[desired:revision=1]",
            "log:step=create-vitalserver-backup status=started",
            "state:vitalserver-backup-requested:VitalServer backup requested:",
            "backup",
        ])
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("log:standard uninstall aborted because VitalServer backup did not complete error=")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("state:failed:VitalServer backup failed:vitalserver-backup-failed:reason=")
        })
    }

    func testUninstallModesBlockBeforeBackupStopOrRemovalWhenConfiguredVitalFilesPathCannotBeRead() {
        for clean in [false, true] {
            let harness = RuntimeUninstallWorkflowHarness(
                externalVitalFilesDirectory: nil,
                configuredVitalFilesDirectoryReadFailure: "permission denied"
            )

            XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: clean)))

            XCTAssertTrue(harness.events.contains {
                $0.contains("state:failed:Vital files ownership unavailable")
                    && $0.contains(
                        "vital-files-ownership-unavailable:reason=host-settings-read-failed:reason=permission denied"
                    )
            })
            XCTAssertFalse(harness.events.contains("backup"))
            XCTAssertFalse(harness.events.contains("stop"))
            XCTAssertFalse(harness.events.contains("log:step=remove-installed-files status=started"))
            XCTAssertTrue(harness.existing.contains("/product"))
            XCTAssertTrue(harness.existing.contains("/default-vital-files"))
        }
    }

    func testForceCleanExplicitlyContinuesWhenConfiguredVitalFilesOwnershipIsUnavailable() throws {
        let harness = RuntimeUninstallWorkflowHarness(
            externalVitalFilesDirectory: nil,
            configuredVitalFilesDirectoryReadFailure: "database unavailable"
        )
        harness.existing.insert("/product/vm/data/vital-files")

        try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(harness.events.contains {
            $0.contains("force-clean destructive recovery override accepted")
                && $0.contains("host-settings-read-failed:reason=database unavailable")
                && $0.contains("preservationLimit=")
        })
        XCTAssertTrue(harness.events.contains {
            $0.contains("force-clean removed only known product-owned Vital files paths")
                && $0.contains("host-settings-read-failed:reason=database unavailable")
        })
        XCTAssertTrue(harness.events.contains("remove:/product/vm/data/vital-files"))
        XCTAssertTrue(harness.events.contains("remove:/default-vital-files"))
        XCTAssertFalse(harness.events.contains("backup"))
    }

    func testStandardUninstallRefusesToReplaceAnExistingRetainedDataDirectory() {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)
        harness.existing.insert(
            "/retained-uninstall-data/tirosh-vitalserver-uninstall-test-preserve"
        )

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false))) { error in
            XCTAssertTrue(error.localizedDescription.contains(
                "refusing to replace existing retained uninstall data"
            ))
        }

        XCTAssertTrue(harness.existing.contains("/product"))
        XCTAssertTrue(harness.existing.contains("/product/logs"))
        XCTAssertFalse(harness.events.contains("log:step=forget-package-receipt status=started"))
    }

    func testStandardUninstallRestoresAlreadyMovedDataWhenRetentionMoveFails() {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)
        harness.moveErrorDestination =
            "/retained-uninstall-data/tirosh-vitalserver-uninstall-test-preserve/backups"

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.existing.contains("/product/logs"))
        XCTAssertTrue(harness.existing.contains("/product/backups"))
        XCTAssertFalse(harness.existing.contains(
            "/retained-uninstall-data/tirosh-vitalserver-uninstall-test-preserve"
        ))
        XCTAssertTrue(harness.events.contains("log:restoring preserved user data after uninstall failure"))
        XCTAssertTrue(harness.events.contains { $0.contains("state:files-removal-blocked") })
    }

    func testStandardUninstallRestoresPreservedDataWhenRemovalFails() {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)
        harness.moveErrorDestination = "/.product.uninstall-test-preserve"

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.events.contains("log:restoring preserved user data after uninstall failure"))
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/logs->/product/logs")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/") && $0.hasSuffix("/backups->/product/backups")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("move:/")
                && $0.hasSuffix("/redis-backups->/product/vm/data/backups/redis")
        })
        XCTAssertTrue(harness.events.contains {
            $0.hasPrefix("state:files-removal-blocked:file removal blocked:file-removal-failed:reason=")
        })
    }

    func testStandardUninstallReportsPreservedDataRestoreFailure() {
        let harness = RuntimeUninstallWorkflowHarness(externalVitalFilesDirectory: nil)
        harness.moveErrorDestination = "/.product.uninstall-test-preserve"
        harness.restoreMoveErrorDestination = "/product/logs"

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
        harness.moveErrorDestination = "/.product.uninstall-test-preserve"
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

    func testUninstallWritesServiceStopBlockedWhenVMStopTimesOut() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.stopError = RuntimeUninstallTestError.stop
        harness.vmProcessState = .stopTimedOut(pid: 84589, timeoutSeconds: 900)

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("vm-process-stop-timed-out:pid=84589 timeout-seconds=900")
        })
        XCTAssertFalse(harness.events.contains("log:uninstall completed"))
    }

    func testCleanUninstallAllowsRuntimeToolAlreadyAbsentDuringRemoval() throws {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.removeAlreadyAbsentPaths = ["/usr/local/bin/vitalserver-proxy-run"]

        try harness.run(RuntimeUninstallCommand(clean: true))

        XCTAssertTrue(harness.events.contains(
            "log:removal target already absent path=/usr/local/bin/vitalserver-proxy-run"
        ))
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testForceCleanUninstallDoesNotCompleteWhenServiceStopIsStillBlocked() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.stopError = RuntimeUninstallTestError.stop
        harness.vmProcessState = .running(pid: 123)

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:service-stop-blocked")
                && $0.contains("vm-process-running:pid=123")
        })
        XCTAssertFalse(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testCleanFlagIsPassedToRuntimeServiceStopEffect() throws {
        let cleanHarness = RuntimeUninstallWorkflowHarness()
        try cleanHarness.run(RuntimeUninstallCommand(clean: true))
        XCTAssertTrue(cleanHarness.events.contains("stop:clean=true"))
        XCTAssertTrue(cleanHarness.events.contains("stop:forceClean=false"))

        let standardHarness = RuntimeUninstallWorkflowHarness()
        try standardHarness.run(RuntimeUninstallCommand(clean: false))
        XCTAssertTrue(standardHarness.events.contains("stop:clean=false"))
        XCTAssertTrue(standardHarness.events.contains("stop:forceClean=false"))
    }

    func testForceCleanFlagIsPassedToRuntimeServiceStopEffect() throws {
        let harness = RuntimeUninstallWorkflowHarness()

        try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(harness.events.contains("stop:clean=true"))
        XCTAssertTrue(harness.events.contains("stop:forceClean=true"))
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
        XCTAssertTrue(harness.events.contains("move:/product->/.product.uninstall-test-preserve"))
        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testCompletedStateRemainsWhenTombstoneDisposalFails() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.removeErrorPath = "/.product.uninstall-test-preserve"

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true))) { error in
            XCTAssertTrue(error.localizedDescription.contains(
                "uninstall completed but state-store tombstone disposal failed"
            ))
        }

        XCTAssertTrue(harness.events.contains("state:completed:uninstall completed:"))
        XCTAssertTrue(harness.events.contains("log:step=dispose-uninstall-state-store status=started"))
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

    func testStandardUninstallDoesNotCompleteWhenSelfRemovingUninstallerRemains() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.cleanupArtifactStates = [
            .present(path: "/usr/local/bin/tirosh-vitalserver-uninstall"),
        ]

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: false)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains(
                    "runtime-artifact-present:path=/usr/local/bin/tirosh-vitalserver-uninstall"
                )
        })
        XCTAssertFalse(harness.events.contains("log:step=forget-package-receipt status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
    }

    func testForceCleanUninstallDoesNotCompleteWhenCleanupArtifactRemains() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.cleanupArtifactStates = [
            .present(path: "/usr/local/bin/vitalserver-vm"),
        ]

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:files-removal-blocked")
                && $0.contains("runtime-artifact-present:path=/usr/local/bin/vitalserver-vm")
        })
        XCTAssertTrue(harness.events.contains("log:step=remove-installed-files status=started"))
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
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

    func testForceCleanUninstallDoesNotCompleteWhenReceiptRemains() {
        let harness = RuntimeUninstallWorkflowHarness()
        harness.updateReceiptsOnForget = false
        harness.receiptStates = [
            .present(identifier: "ai.tirosh.vitalserver.helper"),
        ]

        XCTAssertThrowsError(try harness.run(RuntimeUninstallCommand(clean: true, forceClean: true)))

        XCTAssertTrue(harness.events.contains {
            $0.contains("state:receipts-forget-blocked")
                && $0.contains("package-receipt-present:identifier=ai.tirosh.vitalserver.helper")
        })
        XCTAssertFalse(harness.events.contains("state:completed:uninstall completed:"))
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
    var removeAlreadyAbsentPaths: Set<String> = []
    var moveErrorDestination: String?
    var restoreMoveErrorDestination: String?
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
        self.serviceStates = Dictionary(uniqueKeysWithValues: RuntimeManagedService.uninstallOrder.map {
            ($0, RuntimeServiceState.notLoaded)
        })
        self.existing = [
            "/product",
            "/product/logs",
            "/product/backups",
            "/product/vm/data/backups/redis",
            "/default-vital-files",
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
                runtimeStateDatabase: URL(fileURLWithPath: "/product/vm/runtime/runtime-state.sqlite"),
                managerApp: URL(fileURLWithPath: "/Applications/VitalServer Helper.app"),
                legacyManagedDefaultVitalFilesDirectory: URL(
                    fileURLWithPath: "/product/vm/data/vital-files"
                ),
                sharedManagedDefaultVitalFilesDirectory: URL(
                    fileURLWithPath: "/default-vital-files"
                ),
                retainedDataRoot: URL(fileURLWithPath: "/retained-uninstall-data"),
                configuredVitalFilesDirectoriesRead: configuredVitalFilesDirectoryReadFailure.map {
                    .unavailable(.hostSettingsReadFailed(reason: $0))
                } ?? .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
                    revision: 1,
                    appliedRevision: nil,
                    directories: [
                        RuntimeConfiguredVitalFilesDirectory(
                            source: .desired(revision: 1),
                            directory: URL(fileURLWithPath: externalVitalFilesDirectory ?? "/default-vital-files")
                        ),
                    ]
                )),
                launchDaemonPlists: RuntimeManagedService.uninstallOrder.map {
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
                createVitalServerBackup: {
                    self.events.append("backup")
                    if let backupError = self.backupError {
                        throw backupError
                    }
                },
                stopRuntimeServices: { clean, forceClean in
                    self.events.append("stop")
                    self.events.append("stop:clean=\(clean)")
                    self.events.append("stop:forceClean=\(forceClean)")
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
                acquireOperationLease: {},
                releaseOperationLease: {},
                writeState: { state, _, message, blockers in
                    self.events.append("state:\(state.rawValue):\(message ?? ""):\(blockers.joined(separator: "|"))")
                },
                relocateProductRoot: { source, destination in
                    self.events.append("state-store-relocated:\(source.path)->\(destination.path)")
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
            _ = try removeItem(target)
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
        _ = try removeItem(url)
    }

    private func createDirectory(_ url: URL) {
        events.append("mkdir:\(url.path)")
        existing.insert(url.path)
    }

    private func removeItem(_ url: URL) throws -> RuntimeUninstallRemoveItemResult {
        events.append("remove:\(url.path)")
        if removeErrorPath == url.path {
            throw RuntimeUninstallTestError.remove
        }
        if removeAlreadyAbsentPaths.contains(url.path) {
            existing.remove(url.path)
            return .alreadyAbsent(path: url.path)
        }
        existing.remove(url.path)
        return .removed(path: url.path)
    }

    private func moveItem(from source: URL, to destination: URL) throws {
        events.append("move:\(source.path)->\(destination.path)")
        if destination.path == moveErrorDestination || destination.path == restoreMoveErrorDestination {
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
        paths.append("/product")
        if clean {
            paths.append("/default-vital-files")
            paths.append("/retained-uninstall-data")
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
