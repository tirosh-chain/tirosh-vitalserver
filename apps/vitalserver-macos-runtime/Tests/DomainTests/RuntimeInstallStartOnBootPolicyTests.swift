import Domain
import XCTest

final class RuntimeInstallStartOnBootPolicyTests: XCTestCase {
    func testEnablesSleepPreventionOnlyWhenStartOnBootAndSleepPreventionAreEnabled() {
        let policy = RuntimeInstallStartOnBootPolicy()

        XCTAssertEqual(
            policy.sleepPreventionAction(startOnBoot: true, preventSystemSleep: true),
            .enable
        )
        XCTAssertEqual(
            policy.sleepPreventionAction(startOnBoot: false, preventSystemSleep: true),
            .disable
        )
        XCTAssertEqual(
            policy.sleepPreventionAction(startOnBoot: true, preventSystemSleep: false),
            .disable
        )
        XCTAssertEqual(
            policy.sleepPreventionAction(startOnBoot: false, preventSystemSleep: false),
            .disable
        )
    }
}
