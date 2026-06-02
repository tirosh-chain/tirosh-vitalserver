import Core
import Contracts
import XCTest

final class RuntimeOperationPlanTests: XCTestCase {
    func testInstallPlanStepOrder() {
        XCTAssertEqual(RuntimeOperationPlans.install.operation, .install)
        XCTAssertTrue(RuntimeOperationPlans.install.isValid)
        XCTAssertEqual(RuntimeOperationPlans.install.steps.map(\.rawValue), [
            "load-install-settings",
            "prepare-install-directories",
            "rotate-runtime-logs",
            "configure-guest-runtime-config",
            "prepare-installed-executables",
            "provision-vm-disk",
            "configure-vm-runtime",
            "create-cloud-init-seed",
            "write-install-runtime-version",
            "configure-installed-permissions",
            "start-installed-services",
            "apply-start-on-boot-policy",
            "wait-install-runtime-health",
            "cleanup-install-settings",
        ])
    }

    func testApplyBundlePlanStepOrder() {
        XCTAssertEqual(RuntimeOperationPlans.applyBundle.operation, .applyBundle)
        XCTAssertTrue(RuntimeOperationPlans.applyBundle.isValid)
        XCTAssertEqual(RuntimeOperationPlans.applyBundle.steps.map(\.rawValue), [
            "stop-runtime-services",
            "replace-rootfs-base",
            "replace-update-artifacts",
            "run-migrations",
            "refresh-cloud-init-seed",
            "write-runtime-version",
            "start-runtime-services",
            "activate-guest-update",
            "wait-runtime-health",
        ])
    }

    func testApplyBundlePlanCanSkipRootfsReplacement() {
        let plan = RuntimeOperationPlans.applyBundle(updatesRootfsBase: false)

        XCTAssertEqual(plan.operation, .applyBundle)
        XCTAssertTrue(plan.isValid)
        XCTAssertFalse(plan.steps.contains(.replaceRootfsBase))
        XCTAssertEqual(plan.steps.map(\.rawValue), [
            "stop-runtime-services",
            "replace-update-artifacts",
            "run-migrations",
            "refresh-cloud-init-seed",
            "write-runtime-version",
            "start-runtime-services",
            "activate-guest-update",
            "wait-runtime-health",
        ])
    }

    func testRollbackPlanStepOrder() {
        XCTAssertEqual(RuntimeOperationPlans.rollback.operation, .rollback)
        XCTAssertTrue(RuntimeOperationPlans.rollback.isValid)
        XCTAssertEqual(RuntimeOperationPlans.rollback.steps.map(\.rawValue), [
            "rollback-stop-runtime-services",
            "rollback-restore-rootfs-base",
            "rollback-restore-runtime-version",
            "rollback-restore-update-artifacts",
            "rollback-start-runtime-services",
            "rollback-wait-runtime-health",
        ])
    }

    func testRollbackPlanCanSkipRootfsRestore() {
        let plan = RuntimeOperationPlans.rollback(restoresRootfsBase: false)

        XCTAssertEqual(plan.operation, .rollback)
        XCTAssertTrue(plan.isValid)
        XCTAssertFalse(plan.steps.contains(.rollbackRestoreRootfsBase))
    }

    func testWorkflowStepUnknownRoundTrips() throws {
        let json = #""future-step""#
        let decoded = try JSONDecoder().decode(RuntimeWorkflowStep.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.rawValue, "future-step")

        let encoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(RuntimeWorkflowStep.self, from: encoded)
        XCTAssertEqual(roundTripped.rawValue, "future-step")
    }

    func testWorkflowStepsExposeOwningOperation() {
        XCTAssertEqual(RuntimeWorkflowStep.loadInstallSettings.operation, .install)
        XCTAssertEqual(RuntimeWorkflowStep.waitInstallRuntimeHealth.operation, .install)
        XCTAssertEqual(RuntimeWorkflowStep.stopRuntimeServices.operation, .applyBundle)
        XCTAssertEqual(RuntimeWorkflowStep.rollbackRestoreRootfsBase.operation, .rollback)
        XCTAssertNil(RuntimeWorkflowStep.unknown("future-step").operation)
    }

    func testPlanCreationRejectsStepsThatDoNotBelongToOperation() {
        XCTAssertThrowsError(try RuntimeOperationPlan(
            operation: .install,
            steps: [.loadInstallSettings, .replaceRootfsBase, .unknown("future-step")]
        )) { error in
            XCTAssertEqual(error as? RuntimeOperationPlanValidationError, RuntimeOperationPlanValidationError(
                operation: .install,
                invalidSteps: [.replaceRootfsBase, .unknown("future-step")]
            ))
        }
    }

    func testPlanCanReportInvalidStepsBeforeConstruction() {
        let invalidSteps = RuntimeOperationPlan.invalidSteps(
            operation: .install,
            steps: [.loadInstallSettings, .replaceRootfsBase, .unknown("future-step")]
        )

        XCTAssertEqual(invalidSteps, [.replaceRootfsBase, .unknown("future-step")])
    }
}
