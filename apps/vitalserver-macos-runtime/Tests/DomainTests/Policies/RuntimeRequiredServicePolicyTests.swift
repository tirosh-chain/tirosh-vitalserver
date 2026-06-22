import Contracts
import Application
import Domain
import XCTest
import Errors

final class RuntimeRequiredServicePolicyTests: XCTestCase {
    func testRuntimeManagedServiceStartOrderStartsWatchdogBeforeProxy() {
        XCTAssertEqual(
            RuntimeManagedService.startOrder,
            [
                .vm,
                .guestLogSync,
                .watchdog,
                .proxy,
            ]
        )
    }

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
