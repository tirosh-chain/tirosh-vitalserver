import Application
import Contracts
import Domain
import Foundation
import XCTest
import Errors

final class UpdateRuntimeUseCaseTests: XCTestCase {
    func testInitialHealthDecisionDoesNotWarnWhenRuntimeIsHealthy() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.initialHealthDecision(
            snapshot: healthSnapshot(reasons: [])
        )

        XCTAssertFalse(decision.shouldWarn)
        XCTAssertNil(decision.warningMessage)
    }

    func testInitialHealthDecisionWarnsFromExplicitFailureReasons() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.initialHealthDecision(
            snapshot: healthSnapshot(reasons: [.hostProxyHTTP("000")])
        )

        XCTAssertTrue(decision.shouldWarn)
        XCTAssertEqual(
            decision.warningMessage,
            "bundle apply preflight warning runtime unhealthy reasons=host-proxy-http-000"
        )
    }

    func testApplyBundlePlanIncludesRootfsReplacementWhenPreflightHasRootfs() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.planApplyBundle(for: applyBundlePreflight(stagedRootfs: URL(fileURLWithPath: "/tmp/rootfs")))

        XCTAssertEqual(plan.operationPlan.operation, .applyBundle)
        XCTAssertTrue(plan.operationPlan.steps.contains(.replaceRootfsBase))
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.applyBundle(updatesRootfsBase: true))
    }

    func testApplyBundlePlanSkipsRootfsReplacementWhenPreflightHasNoRootfs() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.planApplyBundle(for: applyBundlePreflight(stagedRootfs: nil))

        XCTAssertEqual(plan.operationPlan.operation, .applyBundle)
        XCTAssertFalse(plan.operationPlan.steps.contains(.replaceRootfsBase))
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.applyBundle(updatesRootfsBase: false))
    }

    func testApplyBundleLifecyclePlansKeepFailureAndRollbackStatusOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.applyBundleStartedPlan(inputPath: "/tmp/bundle.tar.gz"),
            UpdateRuntimeLoggedStatusPlan(
                logMessage: "bundle apply started input=/tmp/bundle.tar.gz",
                status: .updating,
                operation: .applyBundle,
                statusMessage: "bundle apply started"
            )
        )
        XCTAssertEqual(
            useCase.applyBundlePreflightFailedStatusPlan(reason: "manifest missing"),
            UpdateRuntimeStatusPlan(
                status: .critical,
                operation: .applyBundle,
                message: "bundle apply preflight failed: manifest missing"
            )
        )
        XCTAssertEqual(
            useCase.applyBundleRollbackStartedPlan(reason: "replace failed"),
            UpdateRuntimeLoggedStatusPlan(
                logMessage: "bundle apply failed; rolling back error=replace failed",
                status: .recovering,
                operation: .applyBundle,
                statusMessage: "bundle apply failed; rolling back: replace failed"
            )
        )
        XCTAssertEqual(
            useCase.applyBundleRollbackCompletedStatusPlan(reason: "replace failed"),
            UpdateRuntimeStatusPlan(
                status: .degraded,
                operation: .applyBundle,
                message: "bundle apply failed; rollback completed: replace failed"
            )
        )
        XCTAssertEqual(
            useCase.applyBundleRollbackFailedPlan(reason: "rollback failed"),
            UpdateRuntimeLoggedStatusPlan(
                logMessage: "bundle apply rollback failed error=rollback failed",
                status: .critical,
                operation: .applyBundle,
                statusMessage: "bundle apply failed and rollback failed: rollback failed"
            )
        )
    }

    func testApplyBundleCompletionAndBestEffortLogPlansUseExplicitInputs() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.applyBundleCompletedPlan(version: "1.2.3", stagedBundlePath: "/runtime/staged/bundle"),
            UpdateRuntimeLoggedStatusPlan(
                logMessage: "bundle applied path=/runtime/staged/bundle",
                status: .healthy,
                operation: .applyBundle,
                statusMessage: "bundle applied: 1.2.3"
            )
        )
        XCTAssertEqual(
            useCase.applyBundleArtifactCleanupFailedLogMessage(reason: "permission denied"),
            "runtime artifact cleanup failed after bundle apply error=permission denied"
        )
        XCTAssertEqual(
            useCase.applyBundleRollbackFailureServiceRestartFailedLogMessage(reason: "launchd failed"),
            "failed to restart runtime services after rollback failure error=launchd failed"
        )
        XCTAssertEqual(
            useCase.applyBundleLogDirectoryPreparationFailedLogMessage(reason: "permission denied"),
            "bundle apply log directory preparation failed error=permission denied"
        )
        XCTAssertEqual(
            useCase.applyBundleLogRotationFailedLogMessage(reason: "rotate failed"),
            "bundle apply log rotation failed error=rotate failed"
        )
        XCTAssertEqual(
            useCase.mutableVMDiskPreservedLogMessage(path: "/runtime/vm-disk.img"),
            "mutable VM disk preserved path=/runtime/vm-disk.img"
        )
    }

    func testPreflightManifestPlanDerivesExplicitRootfsAndBackupReasonFromManifest() {
        let useCase = UpdateRuntimeUseCase()
        let stagedBundle = URL(fileURLWithPath: "/tmp/staged")

        let plan = useCase.preflightManifestPlan(
            stagedBundle: stagedBundle,
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(name: "rootfs-base.raw.gz", type: .rootfsBase, sha256: "abc", size: 10),
            ])
        )

        XCTAssertEqual(plan.stagedRootfs, stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase))
        XCTAssertEqual(
            plan.manifestLogMessage,
            "bundle apply manifest version=test runtimeVersion=1.0.0 artifacts=1 migrations=0"
        )
        XCTAssertEqual(plan.backupReason, "before-test")
        XCTAssertEqual(plan.backupStartedLogMessage, "creating managed backup reason=before-test")
    }

    func testPreflightManifestPlanPreservesMissingRootfsArtifactAsNoStagedRootfs() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.preflightManifestPlan(
            stagedBundle: URL(fileURLWithPath: "/tmp/staged"),
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10),
            ])
        )

        XCTAssertNil(plan.stagedRootfs)
        XCTAssertEqual(plan.backupReason, "before-test")
    }

    func testPreflightCapabilityPlanRequiresShutdownOnlyWhenVMWillRestart() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.preflightCapabilityPlan(
            manifest: manifest(artifacts: []),
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: true
            )
        )

        XCTAssertTrue(plan.requiresRuntimeDiskHealthCheck)
        XCTAssertEqual(plan.requiredGuestCapabilities, [.prepareUpdateShutdown])
        XCTAssertEqual(
            plan.serviceRestartLogMessage,
            "runtime services before update vm=loaded guestLogSync=loaded proxy=not-loaded watchdog=loaded"
        )
    }

    func testPreflightCapabilityPlanRequiresActivationWhenBundleHasGuestDeploy() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.preflightCapabilityPlan(
            manifest: manifest(artifacts: [
                UpdateBundleArtifact(
                    name: "guest-deploy.tar.gz",
                    type: .guestDeploy,
                    sha256: "abc",
                    size: 10
                ),
            ]),
            restartPolicy: restartPolicy()
        )

        XCTAssertFalse(plan.requiresRuntimeDiskHealthCheck)
        XCTAssertEqual(plan.requiredGuestCapabilities, [.activateUpdate])
        XCTAssertEqual(
            plan.serviceRestartLogMessage,
            "runtime services before update vm=not-loaded guestLogSync=not-loaded proxy=not-loaded watchdog=not-loaded"
        )
    }

    func testStorageRequirementIsPlannedByUseCaseFromExplicitRootfsState() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.storageRequirement(
                stagedBundleBytes: 100,
                rootfsStorage: .unchanged,
                marginBytes: 10
            ),
            RuntimeUpdateStorageRequirement(
                requiredBytes: 110,
                stagedBundleBytes: 100,
                installedRootfsBytes: nil,
                incomingRootfsBytes: nil
            )
        )
        XCTAssertEqual(
            useCase.storageRequirement(
                stagedBundleBytes: 100,
                rootfsStorage: .replacing(installedRootfsBytes: 20, incomingRootfsBytes: 30),
                marginBytes: 10
            ),
            RuntimeUpdateStorageRequirement(
                requiredBytes: 160,
                stagedBundleBytes: 100,
                installedRootfsBytes: 20,
                incomingRootfsBytes: 30
            )
        )
    }

    func testStoragePreflightPlansFormatSizesAndMissingFileFromExplicitInputs() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.storagePreflightStagedBundleLogMessage(stagedBundleBytes: 2_097_152),
            "bundle apply storage preflight stagedBundle=2.0 MiB"
        )

        let replacingPlan = useCase.replacingRootfsStoragePreflightPlan(
            installedRootfsBytes: 1_048_576,
            incomingRootfsBytes: 3_145_728
        )
        XCTAssertEqual(
            replacingPlan.rootfsStorage,
            .replacing(installedRootfsBytes: 1_048_576, incomingRootfsBytes: 3_145_728)
        )
        XCTAssertEqual(
            replacingPlan.logMessage,
            "bundle apply storage preflight installedRootfs=1.0 MiB incomingRootfs=3.0 MiB"
        )

        let unchangedPlan = useCase.unchangedRootfsStoragePreflightPlan()
        XCTAssertEqual(unchangedPlan.rootfsStorage, .unchanged)
        XCTAssertEqual(unchangedPlan.logMessage, "bundle apply storage preflight rootfsBase=unchanged")
        XCTAssertEqual(
            useCase.missingFileFailureMessage(path: "/runtime/missing-rootfs.raw.gz"),
            "missing file: /runtime/missing-rootfs.raw.gz"
        )
        XCTAssertEqual(
            useCase.backupCreatedLogMessage(backupPath: "/runtime/backups/backup-1", backupBytes: 1_048_576),
            "backup created path=/runtime/backups/backup-1 size=1.0 MiB"
        )
    }

    func testRootfsStorageObservationDecisionKeepsFileExistenceInterpretationOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()
        let stagedRootfs = URL(fileURLWithPath: "/staged/rootfs-base.raw.gz")
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")

        XCTAssertEqual(
            useCase.rootfsStorageObservationPlan(stagedRootfs: nil, rootfsBase: rootfsBase),
            .unchanged(ApplyRuntimeBundleRootfsStoragePreflightPlan(
                rootfsStorage: .unchanged,
                logMessage: "bundle apply storage preflight rootfsBase=unchanged"
            ))
        )
        XCTAssertEqual(
            useCase.rootfsStorageObservationPlan(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase),
            .replacing(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
        )
        XCTAssertEqual(
            useCase.rootfsStorageDecision(observation: ApplyRuntimeBundleRootfsStorageObservation(
                stagedRootfs: stagedRootfs,
                stagedRootfsExists: false,
                installedRootfsBytes: nil,
                incomingRootfsBytes: nil
            )),
            .failed(message: "missing file: /staged/rootfs-base.raw.gz")
        )
        XCTAssertEqual(
            useCase.rootfsStorageDecision(observation: ApplyRuntimeBundleRootfsStorageObservation(
                stagedRootfs: stagedRootfs,
                stagedRootfsExists: true,
                installedRootfsBytes: 1_048_576,
                incomingRootfsBytes: 3_145_728
            )),
            .planned(ApplyRuntimeBundleRootfsStoragePreflightPlan(
                rootfsStorage: .replacing(
                    installedRootfsBytes: 1_048_576,
                    incomingRootfsBytes: 3_145_728
                ),
                logMessage: "bundle apply storage preflight installedRootfs=1.0 MiB incomingRootfs=3.0 MiB"
            ))
        )
    }

    func testDiskHealthDecisionAllowsUpdateWithoutGuestStorageBlockers() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.diskHealthDecision(snapshot: healthSnapshot(reasons: []))

        XCTAssertEqual(decision, .allowed)
    }

    func testDiskHealthDecisionBlocksGuestStorageErrorsWithoutFallback() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.diskHealthDecision(snapshot: healthSnapshot(
            reasons: [.init(vmError: .guestFilesystemError)],
            vmErrors: [.guestFilesystemError]
        ))

        XCTAssertEqual(
            decision,
            .blocked(
                blockers: [.guestFilesystemError],
                logMessage: "bundle apply blocked by VM guest storage health errors=vm-guest-filesystem-error",
                failureMessage: "VM disk health blocks update; run Repair VM Disk before applying update. errors=vm-guest-filesystem-error"
            )
        )
    }

    func testStopExecutionPlanPreparesGuestShutdownOnlyWhenVMWillRestart() {
        let useCase = UpdateRuntimeUseCase()
        let manifest = manifest(artifacts: [])

        XCTAssertEqual(
            useCase.stopExecutionPlan(
                restartPolicy: RuntimeServiceRestartPolicy(
                    restartVM: true,
                    restartGuestLogSync: false,
                    restartProxy: false,
                    restartWatchdog: false
                ),
                manifest: manifest
            ),
            .prepareGuestShutdownAndStopServicesAfterPoweroff(manifest: manifest)
        )
        XCTAssertEqual(
            useCase.stopExecutionPlan(restartPolicy: restartPolicy(), manifest: manifest),
            .stopServicesDirectly
        )
    }

    func testRootfsReplacementPlanKeepsMissingRootfsAsExplicitSkip() {
        let useCase = UpdateRuntimeUseCase()
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw")
        let stagedRootfs = URL(fileURLWithPath: "/tmp/rootfs-base.raw.gz")

        let skipPlan = useCase.rootfsReplacementPlan(stagedRootfs: nil, rootfsBase: rootfsBase)
        let replacePlan = useCase.rootfsReplacementPlan(
            stagedRootfs: stagedRootfs,
            rootfsBase: rootfsBase
        )

        XCTAssertEqual(
            skipPlan,
            .skip(logMessage: "rootfs-base replacement skipped; bundle does not include rootfs-base")
        )
        XCTAssertEqual(replacePlan, .replace(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase))
    }

    func testApplyBundleStepExecutionMessagesComeFromUseCase() {
        let useCase = UpdateRuntimeUseCase()
        let stagedRootfs = URL(fileURLWithPath: "/staged/rootfs-base.raw.gz")
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        let executionPlan = useCase.rootfsReplacementExecutionPlan(
            stagedRootfs: stagedRootfs,
            rootfsBase: rootfsBase,
            stagedRootfsBytes: 1_048_576
        )

        XCTAssertEqual(
            useCase.capturedVMProcessBeforeGuestUpdateShutdownLogMessage(processID: 123),
            "captured VM process before guest update shutdown pid=123"
        )
        XCTAssertEqual(
            executionPlan.startedLogMessage,
            "replacing rootfs-base source=/staged/rootfs-base.raw.gz destination=/runtime/rootfs-base.raw.gz size=1.0 MiB"
        )
        XCTAssertEqual(
            executionPlan.completedLogMessage,
            "rootfs-base replaced destination=/runtime/rootfs-base.raw.gz"
        )
        XCTAssertEqual(
            useCase.unsupportedApplyBundleStepFailureMessage(step: .loadInstallSettings),
            "unsupported command: apply-bundle step load-install-settings"
        )
        XCTAssertEqual(
            useCase.unsupportedRollbackStepFailureMessage(step: .loadInstallSettings),
            "unsupported command: rollback step load-install-settings"
        )
        XCTAssertEqual(
            useCase.rollbackRootfsRestoreMissingBackupRootfsFailureMessage(),
            "rollback rootfs restore requested without backup rootfs"
        )
        XCTAssertEqual(
            useCase.guestShutdownPreparationCleanupFailedLogMessage(reason: "permission denied"),
            "guest shutdown preparation cleanup failed error=permission denied"
        )
    }

    func testApplyBundleStepExecutionPlansKeepStepInterpretationOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()
        let stagedBundle = URL(fileURLWithPath: "/tmp/staged")
        let stagedRootfs = stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        let artifact = UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10)
        let migration = UpdateBundleMigration(name: "001-test", sha256: "def", size: 20)
        let manifest = UpdateBundleManifest(
            schemaVersion: 1,
            product: "vitalserver",
            helperVersion: "1.0.0",
            releaseLabel: "test",
            targetPlatform: "macos",
            components: [:],
            createdAt: "2026-06-06T00:00:00Z",
            artifacts: [artifact],
            migrations: [migration]
        )
        let restartPolicy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: false,
            restartProxy: true,
            restartWatchdog: false
        )
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: stagedBundle,
            manifest: manifest,
            stagedRootfs: stagedRootfs,
            backup: URL(fileURLWithPath: "/tmp/backup"),
            restartPolicy: restartPolicy
        )

        XCTAssertEqual(
            useCase.applyBundleStepExecutionPlan(
                step: .stopRuntimeServices,
                preflight: preflight,
                rootfsBase: rootfsBase
            ),
            .stopRuntimeServices(.prepareGuestShutdownAndStopServicesAfterPoweroff(manifest: manifest))
        )
        XCTAssertEqual(
            useCase.applyBundleStepExecutionPlan(
                step: .replaceRootfsBase,
                preflight: preflight,
                rootfsBase: rootfsBase
            ),
            .replaceRootfsBase(.replace(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase))
        )
        XCTAssertEqual(
            useCase.applyBundleStepExecutionPlan(
                step: .replaceRootfsBase,
                preflight: ApplyBundlePreflightContext(
                    stagedBundle: stagedBundle,
                    manifest: manifest,
                    stagedRootfs: nil,
                    backup: URL(fileURLWithPath: "/tmp/backup"),
                    restartPolicy: restartPolicy
                ),
                rootfsBase: rootfsBase
            ),
            .replaceRootfsBase(.skip(logMessage: "rootfs-base replacement skipped; bundle does not include rootfs-base"))
        )
        XCTAssertEqual(
            useCase.applyBundleStepExecutionPlan(
                step: .runMigrations,
                preflight: preflight,
                rootfsBase: rootfsBase
            ),
            .runMigrations(migrations: [migration], stagedBundle: stagedBundle)
        )
        XCTAssertEqual(
            useCase.applyBundleStepExecutionPlan(
                step: .loadInstallSettings,
                preflight: preflight,
                rootfsBase: rootfsBase
            ),
            .unsupported(failureMessage: "unsupported command: apply-bundle step load-install-settings")
        )
    }

    func testRollbackPlanIncludesRootfsRestoreWhenPreflightRestoresRootfs() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.planRollback(for: rollbackPreflight(restoresRootfsBase: true))

        XCTAssertEqual(plan.operationPlan.operation, .rollback)
        XCTAssertTrue(plan.operationPlan.steps.contains(.rollbackRestoreRootfsBase))
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.rollback(restoresRootfsBase: true))
    }

    func testRollbackPlanSkipsRootfsRestoreWhenPreflightDoesNotRestoreRootfs() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.planRollback(for: rollbackPreflight(restoresRootfsBase: false))

        XCTAssertEqual(plan.operationPlan.operation, .rollback)
        XCTAssertFalse(plan.operationPlan.steps.contains(.rollbackRestoreRootfsBase))
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.rollback(restoresRootfsBase: false))
    }

    func testRollbackLifecyclePlansKeepStatusAndProgressMessagesOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()
        let event = RuntimeStepExecutionEvent(
            operation: .rollback,
            status: .recovering,
            step: .rollbackRestoreRuntimeVersion,
            stepStatus: .completed,
            phase: .running,
            message: "restored"
        )

        XCTAssertEqual(
            useCase.rollbackStartedPlan(backupPath: "/runtime/backups/backup-1"),
            UpdateRuntimeLoggedStatusPlan(
                logMessage: "rollback started backup=/runtime/backups/backup-1",
                status: .recovering,
                operation: .rollback,
                statusMessage: "rollback started"
            )
        )
        XCTAssertEqual(
            useCase.rollbackProgressLogMessage(event: event),
            "step=rollback-restore-runtime-version status=completed"
        )
        XCTAssertEqual(
            useCase.rollbackCompletedPlan(
                backupPath: "/runtime/backups/backup-1",
                vmDiskPath: "/runtime/vm/vm-disk.img"
            ),
            RollbackRuntimeCompletionPlan(
                statusPlan: UpdateRuntimeStatusPlan(
                    status: .healthy,
                    operation: .rollback,
                    message: "rollback completed"
                ),
                restoredBackupLogMessage: "rollback restored backup=/runtime/backups/backup-1",
                preservedVMDiskLogMessage: "mutable VM disk preserved path=/runtime/vm/vm-disk.img"
            )
        )
    }

    func testRollbackStepExecutionPlansKeepStepInterpretationOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        let backupRootfs = backup.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backupRootfs,
            backupVersion: backup.appendingPathComponent(RuntimeFileNames.runtimeVersion),
            restoresRootfsBase: true,
            restartPolicy: restartPolicy()
        )
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        let runtimeVersion = URL(fileURLWithPath: "/runtime/runtime-version.json")
        let managerAppPath = URL(fileURLWithPath: "/Applications/VitalServer.app")
        let nginxDirectory = URL(fileURLWithPath: "/runtime/nginx")
        let deployDirectory = URL(fileURLWithPath: "/runtime/deploy")

        XCTAssertEqual(
            useCase.rollbackStepExecutionPlan(
                step: .rollbackRestoreRootfsBase,
                preflight: preflight,
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory,
                backupVersionExists: true
            ),
            .restoreRootfsBase(source: backupRootfs, destination: rootfsBase)
        )
        XCTAssertEqual(
            useCase.rollbackStepRequiredInput(
                step: .rollbackRestoreRuntimeVersion,
                preflight: preflight
            ),
            .backupVersionExists(backup.appendingPathComponent(RuntimeFileNames.runtimeVersion))
        )
        XCTAssertEqual(
            useCase.rollbackStepRequiredInput(
                step: .rollbackStopRuntimeServices,
                preflight: preflight
            ),
            .none
        )
        XCTAssertEqual(
            useCase.rollbackStepExecutionPlan(
                step: .rollbackRestoreRuntimeVersion,
                preflight: preflight,
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory,
                backupVersionExists: false
            ),
            .restoreRuntimeVersion(.writeExplicitRollbackMarker(version: "rolled-back", destinationDirectory: backup))
        )
        XCTAssertEqual(
            useCase.rollbackStepRequiredInput(
                step: .rollbackRestoreRuntimeVersion,
                preflight: preflight
            ),
            .backupVersionExists(backup.appendingPathComponent(RuntimeFileNames.runtimeVersion))
        )
        XCTAssertEqual(
            useCase.rollbackStepRequiredInput(
                step: .rollbackRestoreRootfsBase,
                preflight: preflight
            ),
            .none
        )
        XCTAssertEqual(
            useCase.rollbackStepExecutionPlan(
                step: .rollbackRestoreRootfsBase,
                preflight: rollbackPreflight(restoresRootfsBase: false),
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory,
                backupVersionExists: true
            ),
            .failed(failureMessage: "rollback rootfs restore requested without backup rootfs")
        )
        XCTAssertEqual(
            useCase.rollbackStepExecutionPlan(
                step: .stopRuntimeServices,
                preflight: preflight,
                rootfsBase: rootfsBase,
                runtimeVersion: runtimeVersion,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory,
                backupVersionExists: true
            ),
            .unsupported(failureMessage: "unsupported command: rollback step stop-runtime-services")
        )
    }

    func testRollbackBackupPlanPreservesManifestRootfsAsExplicitRestoreState() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")

        let plan = useCase.rollbackBackupPlan(
            backup: backup,
            manifest: backupManifest(rootfsBase: "rootfs-base.raw.gz")
        )

        XCTAssertEqual(plan.backup, backup)
        XCTAssertEqual(plan.backupRootfs, backup.appendingPathComponent("rootfs-base.raw.gz"))
        XCTAssertEqual(plan.backupVersion, backup.appendingPathComponent(RuntimeFileNames.runtimeVersion))
        XCTAssertTrue(plan.restoresRootfsBase)
    }

    func testRollbackBackupPlanPreservesMissingRootfsAsNoRestoreWithoutFallback() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")

        let plan = useCase.rollbackBackupPlan(
            backup: backup,
            manifest: backupManifest(rootfsBase: nil)
        )

        XCTAssertEqual(plan.backup, backup)
        XCTAssertNil(plan.backupRootfs)
        XCTAssertEqual(plan.backupVersion, backup.appendingPathComponent(RuntimeFileNames.runtimeVersion))
        XCTAssertFalse(plan.restoresRootfsBase)
    }

    func testRollbackPreflightDecisionsKeepBackupExistenceInterpretationOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        let backupPlan = useCase.rollbackBackupPlan(
            backup: backup,
            manifest: backupManifest(rootfsBase: RuntimeFileNames.rootfsBase)
        )
        let noRootfsPlan = useCase.rollbackBackupPlan(
            backup: backup,
            manifest: backupManifest(rootfsBase: nil)
        )

        XCTAssertEqual(
            useCase.rollbackBackupDirectoryDecision(backup: backup, directoryExists: true),
            .loadManifest(backup)
        )
        XCTAssertEqual(
            useCase.rollbackBackupDirectoryDecision(backup: backup, directoryExists: false),
            .failed(message: "missing file: /runtime/backups/backup-1")
        )
        XCTAssertEqual(
            useCase.rollbackBackupRootfsObservationRequirement(backupPlan: backupPlan),
            .fileExists(backup.appendingPathComponent(RuntimeFileNames.rootfsBase))
        )
        XCTAssertEqual(
            useCase.rollbackBackupRootfsDecision(
                backupPlan: backupPlan,
                backupRootfsExists: false
            ),
            .failed(message: "missing file: /runtime/backups/backup-1/rootfs-base.raw.gz")
        )
        XCTAssertEqual(
            useCase.rollbackBackupRootfsObservationRequirement(backupPlan: noRootfsPlan),
            .none
        )
        XCTAssertEqual(
            useCase.rollbackBackupRootfsDecision(
                backupPlan: noRootfsPlan,
                backupRootfsExists: nil
            ),
            .proceed(noRootfsPlan)
        )
    }

    func testRollbackBackupSelectionKeepsCommandInterpretationOutOfWorkflow() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")

        XCTAssertEqual(useCase.rollbackBackupSelection(command: .latestBackup), .latestBackup)
        XCTAssertEqual(
            useCase.rollbackBackupSelection(command: .specificBackup(backup)),
            .specificBackup(backup)
        )
    }

    func testBundlePreparationMessagesComeFromUseCase() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.bundleVerificationStartedLogMessage(sourcePath: "/input/update-bundle.tar.gz"),
            "bundle verification started path=/input/update-bundle.tar.gz"
        )
        XCTAssertEqual(
            useCase.bundleStageStartedLogMessage(sourcePath: "/input/update-bundle.tar.gz"),
            "bundle stage started source=/input/update-bundle.tar.gz"
        )
    }

    func testRollbackPreflightPlanFormatsRestartPolicyFromExplicitServiceState() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")

        let plan = useCase.rollbackPreflightPlan(
            backup: backup,
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: false,
                restartProxy: true,
                restartWatchdog: false
            )
        )

        XCTAssertEqual(
            plan.serviceRestartLogMessage,
            "rollback preflight backup=/runtime/backups/backup-1 vm=loaded guestLogSync=not-loaded proxy=loaded watchdog=not-loaded"
        )
    }

    func testRollbackVersionRestoreDecisionPreservesMissingBackupVersionAsExplicitMarkerWrite() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")
        let backupVersion = backup.appendingPathComponent(RuntimeFileNames.runtimeVersion)
        let runtimeVersion = URL(fileURLWithPath: "/runtime/version.json")

        XCTAssertEqual(
            useCase.rollbackVersionRestoreDecision(
                backupVersion: backupVersion,
                runtimeVersion: runtimeVersion,
                backupVersionExists: true,
                backup: backup
            ),
            .restoreBackupVersion(source: backupVersion, destination: runtimeVersion)
        )
        XCTAssertEqual(
            useCase.rollbackVersionRestoreDecision(
                backupVersion: backupVersion,
                runtimeVersion: runtimeVersion,
                backupVersionExists: false,
                backup: backup
            ),
            .writeExplicitRollbackMarker(version: "rolled-back", destinationDirectory: backup)
        )
    }

    func testRollbackManagedArtifactRestorePlanMapsExplicitBackupArtifacts() {
        let useCase = UpdateRuntimeUseCase()
        let backup = URL(fileURLWithPath: "/runtime/backups/backup-1")

        let plan = useCase.rollbackManagedArtifactRestorePlan(
            backup: backup,
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer.app"),
            nginxDirectory: URL(fileURLWithPath: "/runtime/nginx"),
            deployDirectory: URL(fileURLWithPath: "/runtime/deploy")
        )

        XCTAssertEqual(plan.directoryRestores, [
            RollbackRuntimeManagedArtifactRestore(
                backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.appBundle.rawValue),
                restoreDestination: URL(fileURLWithPath: "/Applications/VitalServer.app")
            ),
            RollbackRuntimeManagedArtifactRestore(
                backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.nginxBundle.rawValue),
                restoreDestination: URL(fileURLWithPath: "/runtime/nginx")
            ),
            RollbackRuntimeManagedArtifactRestore(
                backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.guestDeploy.rawValue),
                restoreDestination: URL(fileURLWithPath: "/runtime/deploy")
            ),
        ])
        XCTAssertEqual(
            plan.runtimeToolsBackup,
            backup.appendingPathComponent(UpdateBundleArtifactType.runtimeTools.rawValue)
        )
    }

    func testGuestActivationPlanRequiresActivationOnlyForGuestDeployArtifact() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.guestActivationPlan(manifest: manifest(artifacts: [
            UpdateBundleArtifact(name: "guest-deploy.tar.gz", type: .guestDeploy, sha256: "abc", size: 10),
        ]))

        XCTAssertTrue(plan.requiresActivation)
        XCTAssertEqual(plan.version, "test")
        XCTAssertNil(plan.skippedLogMessage)
        XCTAssertEqual(plan.requestedLogMessage, "guest update activation requested version=test")
        XCTAssertEqual(plan.completedLogMessage, "guest update activation completed version=test")
    }

    func testGuestActivationPlanPreservesNoGuestDeployAsExplicitSkipWithoutRequestFallback() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.guestActivationPlan(manifest: manifest(artifacts: [
            UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10),
        ]))
        let request = useCase.guestActivationRequest(
            plan: plan,
            requestID: "request-1",
            requestedAt: "2026-06-06T00:00:00Z"
        )

        XCTAssertFalse(plan.requiresActivation)
        XCTAssertEqual(plan.version, "test")
        XCTAssertEqual(plan.skippedLogMessage, "guest update activation not required")
        XCTAssertNil(plan.requestedLogMessage)
        XCTAssertNil(plan.completedLogMessage)
        XCTAssertNil(request)
    }

    func testGuestActivationRequestUsesExplicitRequestStateAndPlannedVersion() {
        let useCase = UpdateRuntimeUseCase()
        let plan = useCase.guestActivationPlan(manifest: manifest(artifacts: [
            UpdateBundleArtifact(name: "guest-deploy.tar.gz", type: .guestDeploy, sha256: "abc", size: 10),
        ]))

        let request = useCase.guestActivationRequest(
            plan: plan,
            requestID: "request-1",
            requestedAt: "2026-06-06T00:00:00Z"
        )

        XCTAssertEqual(request?.id, "request-1")
        XCTAssertEqual(request?.requestedAt, "2026-06-06T00:00:00Z")
        XCTAssertEqual(request?.version, "test")
    }

    func testGuestActivationWaitResultPlanPreservesFailureAndTimeoutWithoutWorkflowJudgement() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.guestActivationWaitStartedLogMessage(timeoutSeconds: 180),
            "waiting for guest update activation result timeoutSeconds=180.0"
        )
        XCTAssertEqual(
            useCase.guestActivationRequiredRequestMissingFailureMessage(),
            "guest activation request missing for required activation"
        )
        XCTAssertEqual(
            useCase.guestActivationWaitResultPlan(.completed(message: "done")),
            RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result completed message=done",
                failureMessage: nil
            )
        )
        XCTAssertEqual(
            useCase.guestActivationWaitResultPlan(.failed(message: "compose failed")),
            RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result failed message=compose failed",
                failureMessage: "runtime health check failed"
            )
        )
        XCTAssertEqual(
            useCase.guestActivationWaitResultPlan(.timedOut),
            RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        )
    }

    func testGuestShutdownPlanAndRequestUseExplicitVersionRequestState() {
        let useCase = UpdateRuntimeUseCase()

        let plan = useCase.guestShutdownPlan(version: "1.2.3")
        let request = useCase.guestShutdownRequest(
            plan: plan,
            requestID: "request-1",
            requestedAt: "2026-06-06T00:00:00Z"
        )

        XCTAssertEqual(plan.version, "1.2.3")
        XCTAssertEqual(plan.requestedLogMessage, "guest update shutdown requested version=1.2.3")
        XCTAssertEqual(plan.readyLogMessage, "guest update shutdown ready version=1.2.3")
        XCTAssertEqual(request.id, "request-1")
        XCTAssertEqual(request.requestedAt, "2026-06-06T00:00:00Z")
        XCTAssertEqual(request.version, "1.2.3")
    }

    func testGuestShutdownWaitResultPlanPreservesGuestFailureAndTimeoutSeparately() {
        let useCase = UpdateRuntimeUseCase()

        XCTAssertEqual(
            useCase.guestShutdownWaitStartedLogMessage(timeoutSeconds: 300),
            "waiting for guest update shutdown result timeoutSeconds=300.0"
        )
        XCTAssertEqual(
            useCase.guestShutdownWaitResultPlan(.ready(message: "poweroff requested")),
            RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result ready message=poweroff requested",
                failureMessage: nil
            )
        )
        XCTAssertEqual(
            useCase.guestShutdownWaitResultPlan(.failed(message: "backup failed")),
            RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result failed message=backup failed",
                failureMessage: "backup failed"
            )
        )
        XCTAssertEqual(
            useCase.guestShutdownWaitResultPlan(.timedOut),
            RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "guest update shutdown timed out"
            )
        )
    }

    func testGuestCapabilityDecisionPreservesLoadedMissingAndFailedStateSeparately() {
        let useCase = UpdateRuntimeUseCase()
        let supportedState = GuestRuntimeStateDocument(
            capabilities: GuestRuntimeCapabilities(
                prepareUpdateShutdown: true,
                activateUpdate: false,
                redisBackup: false,
                repairDatastore: false
            ),
            vmIP: "192.168.64.2",
            guestHTTP: nil,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil
        )
        let unsupportedState = GuestRuntimeStateDocument(
            capabilities: nil,
            vmIP: "192.168.64.2",
            guestHTTP: nil,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil
        )

        XCTAssertEqual(
            useCase.guestCapabilityDecision(
                loadResult: .loaded(supportedState),
                capability: .prepareUpdateShutdown
            ),
            RuntimeGuestCapabilityDecision(isSupported: true, failure: nil)
        )
        XCTAssertEqual(
            useCase.guestCapabilityDecision(
                loadResult: .loaded(unsupportedState),
                capability: .prepareUpdateShutdown
            ),
            RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .missingCapability("prepare-update-shutdown")
            )
        )
        XCTAssertEqual(
            useCase.guestCapabilityDecision(
                loadResult: .missing,
                capability: .activateUpdate
            ),
            RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .missingRuntimeState("activate-update")
            )
        )
        XCTAssertEqual(
            useCase.guestCapabilityDecision(
                loadResult: .failed("permission denied"),
                capability: .activateUpdate
            ),
            RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .runtimeStateReadFailed(
                    capability: "activate-update",
                    reason: "permission denied"
                )
            )
        )
    }
}

private func applyBundlePreflight(stagedRootfs: URL?) -> ApplyBundlePreflightContext {
    ApplyBundlePreflightContext(
        stagedBundle: URL(fileURLWithPath: "/tmp/bundle"),
        manifest: UpdateBundleManifest(
            schemaVersion: 1,
            product: "vitalserver",
            helperVersion: "1.0.0",
            releaseLabel: "test",
            targetPlatform: "macos",
            components: [:],
            createdAt: "2026-06-06T00:00:00Z",
            artifacts: [],
            migrations: []
        ),
        stagedRootfs: stagedRootfs,
        backup: URL(fileURLWithPath: "/tmp/backup"),
        restartPolicy: restartPolicy()
    )
}

private func manifest(artifacts: [UpdateBundleArtifact]) -> UpdateBundleManifest {
    UpdateBundleManifest(
        schemaVersion: 1,
        product: "vitalserver",
        helperVersion: "1.0.0",
        releaseLabel: "test",
        targetPlatform: "macos",
        components: [:],
        createdAt: "2026-06-06T00:00:00Z",
        artifacts: artifacts,
        migrations: []
    )
}

private func rollbackPreflight(restoresRootfsBase: Bool) -> RollbackPreflightContext {
    RollbackPreflightContext(
        backup: URL(fileURLWithPath: "/tmp/backup"),
        backupRootfs: restoresRootfsBase ? URL(fileURLWithPath: "/tmp/backup/rootfs") : nil,
        backupVersion: URL(fileURLWithPath: "/tmp/backup/version.json"),
        restoresRootfsBase: restoresRootfsBase,
        restartPolicy: restartPolicy()
    )
}

private func backupManifest(rootfsBase: String?) -> BackupManifest {
    BackupManifest(
        product: "ai.tirosh.vitalserver.helper",
        createdAt: "2026-06-06T00:00:00Z",
        reason: "before-1.2.3",
        rootfsBase: rootfsBase,
        vmDisk: "vm-disk.img",
        vmDiskPreserved: true
    )
}

private func restartPolicy() -> RuntimeServiceRestartPolicy {
    RuntimeServiceRestartPolicy(
        restartVM: false,
        restartGuestLogSync: false,
        restartProxy: false,
        restartWatchdog: false
    )
}

private func healthSnapshot(
    reasons: [RuntimeFailureReason],
    vmErrors: [RuntimeVMError] = []
) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: true,
        proxyExecutable: true,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: reasons.isEmpty ? .running : .unreachable,
        vmErrors: vmErrors,
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: reasons.isEmpty ? "200" : "000",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
