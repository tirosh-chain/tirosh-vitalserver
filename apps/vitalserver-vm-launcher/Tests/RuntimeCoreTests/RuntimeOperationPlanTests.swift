import RuntimeCore
import XCTest

final class RuntimeOperationPlanTests: XCTestCase {
    func testInstallPlanStepOrder() {
        XCTAssertEqual(RuntimeOperationPlans.install.operation, .install)
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
            "cleanup-install-settings",
        ])
    }

    func testApplyBundlePlanStepOrder() {
        XCTAssertEqual(RuntimeOperationPlans.applyBundle.operation, .applyBundle)
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

    func testRollbackPlanStepOrder() {
        XCTAssertEqual(RuntimeOperationPlans.rollback.operation, .rollback)
        XCTAssertEqual(RuntimeOperationPlans.rollback.steps.map(\.rawValue), [
            "rollback-stop-runtime-services",
            "rollback-restore-rootfs-base",
            "rollback-restore-runtime-version",
            "rollback-restore-update-artifacts",
            "rollback-start-runtime-services",
            "rollback-wait-runtime-health",
        ])
    }

    func testWorkflowStepUnknownRoundTrips() throws {
        let json = #""future-step""#
        let decoded = try JSONDecoder().decode(RuntimeWorkflowStep.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.rawValue, "future-step")

        let encoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(RuntimeWorkflowStep.self, from: encoded)
        XCTAssertEqual(roundTripped.rawValue, "future-step")
    }
}
