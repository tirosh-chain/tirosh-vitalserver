import Contracts
import Domain
import XCTest
import Errors

final class DomainRuntimeOperationPlanTests: XCTestCase {
    func testInstallPlanStepOrderIsDomainPolicy() {
        XCTAssertEqual(RuntimeOperationPlans.install.operation, .install)
        XCTAssertTrue(RuntimeOperationPlans.install.isValid)
        XCTAssertEqual(RuntimeOperationPlans.install.steps.first, .loadInstallSettings)
        XCTAssertEqual(RuntimeOperationPlans.install.steps.last, .cleanupInstallSettings)
        XCTAssertTrue(RuntimeOperationPlans.install.steps.contains(.waitInstallRuntimeHealth))
    }

    func testInstallProvisionPlanDoesNotClaimRuntimeHealth() {
        XCTAssertEqual(RuntimeOperationPlans.installProvision.operation, .install)
        XCTAssertTrue(RuntimeOperationPlans.installProvision.isValid)
        XCTAssertFalse(RuntimeOperationPlans.installProvision.steps.contains(.waitInstallRuntimeHealth))
    }

    func testPlanCreationRejectsStepsOutsideOperation() {
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
}
