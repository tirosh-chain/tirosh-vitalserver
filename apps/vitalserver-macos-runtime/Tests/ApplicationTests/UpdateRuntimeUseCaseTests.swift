import Application
import Contracts
import Domain
import Foundation
import XCTest
import Errors

final class UpdateRuntimeUseCaseTests: XCTestCase {
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

private func rollbackPreflight(restoresRootfsBase: Bool) -> RollbackPreflightContext {
    RollbackPreflightContext(
        backup: URL(fileURLWithPath: "/tmp/backup"),
        backupRootfs: restoresRootfsBase ? URL(fileURLWithPath: "/tmp/backup/rootfs") : nil,
        backupVersion: URL(fileURLWithPath: "/tmp/backup/version.json"),
        restoresRootfsBase: restoresRootfsBase,
        restartPolicy: restartPolicy()
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
