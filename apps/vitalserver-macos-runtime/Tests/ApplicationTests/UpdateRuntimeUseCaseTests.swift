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
            snapshot: healthSnapshot(reasons: []),
            reasonText: "should-not-leak"
        )

        XCTAssertFalse(decision.shouldWarn)
        XCTAssertNil(decision.warningMessage)
    }

    func testInitialHealthDecisionWarnsFromExplicitFailureReasons() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.initialHealthDecision(
            snapshot: healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            reasonText: "host-proxy-http-000"
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

    func testDiskHealthDecisionAllowsUpdateWithoutGuestStorageBlockers() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.diskHealthDecision(snapshot: healthSnapshot(reasons: []))

        XCTAssertTrue(decision.canApplyUpdate)
        XCTAssertEqual(decision.blockers, [])
        XCTAssertNil(decision.blockedLogMessage)
        XCTAssertNil(decision.failureMessage)
    }

    func testDiskHealthDecisionBlocksGuestStorageErrorsWithoutFallback() {
        let useCase = UpdateRuntimeUseCase()

        let decision = useCase.diskHealthDecision(snapshot: healthSnapshot(
            reasons: [.init(vmError: .guestFilesystemError)],
            vmErrors: [.guestFilesystemError]
        ))

        XCTAssertFalse(decision.canApplyUpdate)
        XCTAssertEqual(decision.blockers, [.guestFilesystemError])
        XCTAssertEqual(
            decision.blockedLogMessage,
            "bundle apply blocked by VM guest storage health errors=vm-guest-filesystem-error"
        )
        XCTAssertEqual(
            decision.failureMessage,
            "VM disk health blocks update; run Repair VM Disk before applying update. errors=vm-guest-filesystem-error"
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
