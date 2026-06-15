import Application
import Contracts
import XCTest

final class ApplyRuntimeInstallStartOnBootPolicyUseCaseTests: XCTestCase {
    func testPlansSleepPreventionActionFromExplicitInstallSettings() {
        let useCase = ApplyRuntimeInstallStartOnBootPolicyUseCase()

        XCTAssertEqual(
            useCase.plan(input: RuntimeInstallStartOnBootPolicyInput(
                startOnBoot: true,
                preventSystemSleep: true
            )),
            RuntimeInstallStartOnBootPlan(startOnBoot: true, sleepPreventionAction: .enable)
        )
        XCTAssertEqual(
            useCase.plan(input: RuntimeInstallStartOnBootPolicyInput(
                startOnBoot: false,
                preventSystemSleep: true
            )),
            RuntimeInstallStartOnBootPlan(startOnBoot: false, sleepPreventionAction: .disable)
        )
        XCTAssertEqual(
            useCase.plan(input: RuntimeInstallStartOnBootPolicyInput(
                startOnBoot: true,
                preventSystemSleep: false
            )),
            RuntimeInstallStartOnBootPlan(startOnBoot: true, sleepPreventionAction: .disable)
        )
    }
}
