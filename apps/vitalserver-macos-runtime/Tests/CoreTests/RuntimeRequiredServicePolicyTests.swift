import Contracts
import Core
import XCTest

final class RuntimeRequiredServicePolicyTests: XCTestCase {
    func testAllRuntimeServicesPolicyIncludesGuestLogSync() {
        let policy = RuntimeRequiredServicePolicy.allRuntimeServices

        XCTAssertEqual(
            RuntimeRequiredServicePolicy.requiredServices(for: policy),
            [
                .vm,
                .guestLogSync,
                .proxy,
                .watchdog,
            ]
        )
    }

    func testRequiredServicesFollowExplicitRestartPolicy() {
        let policy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: false,
            restartProxy: true,
            restartWatchdog: false
        )

        XCTAssertEqual(
            RuntimeRequiredServicePolicy.requiredServices(for: policy),
            [
                .vm,
                .proxy,
            ]
        )
    }
}
