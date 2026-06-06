import Contracts
import Domain
import Errors
import OutboundAdapters
import XCTest

final class RuntimeServiceStopWaiterTests: XCTestCase {
    func testWaitReturnsImmediatelyWhenServiceIsNotLoaded() throws {
        var sleeps: [TimeInterval] = []
        let waiter = RuntimeServiceStopWaiter(
            serviceState: { _ in .notLoaded },
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { sleeps.append($0) },
            waitForVMProcessStoppedAfterServiceUnload: {},
            vmStopTimeoutSeconds: 10,
            serviceStopTimeoutSeconds: 3,
            pollIntervalSeconds: 0.5
        )

        try waiter.waitUntilStopped(.proxy)

        XCTAssertTrue(sleeps.isEmpty)
    }

    func testWaitPollsLoadedServiceUntilExplicitlyNotLoaded() throws {
        var states: [RuntimeServiceState] = [.loaded, .loaded, .notLoaded]
        var sleeps: [TimeInterval] = []
        var currentTime = Date(timeIntervalSince1970: 0)
        let waiter = RuntimeServiceStopWaiter(
            serviceState: { _ in states.removeFirst() },
            now: { currentTime },
            sleep: { interval in
                sleeps.append(interval)
                currentTime = currentTime.addingTimeInterval(interval)
            },
            waitForVMProcessStoppedAfterServiceUnload: {},
            vmStopTimeoutSeconds: 10,
            serviceStopTimeoutSeconds: 3,
            pollIntervalSeconds: 0.5
        )

        try waiter.waitUntilStopped(.proxy)

        XCTAssertEqual(sleeps, [0.5, 0.5])
    }

    func testReadFailureDoesNotFallbackToStopped() {
        let waiter = RuntimeServiceStopWaiter(
            serviceState: { _ in .readFailed("launchctl denied") },
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { _ in XCTFail("read failure must not sleep or retry as success") },
            waitForVMProcessStoppedAfterServiceUnload: {},
            vmStopTimeoutSeconds: 10,
            serviceStopTimeoutSeconds: 3,
            pollIntervalSeconds: 0.5
        )

        XCTAssertThrowsError(try waiter.waitUntilStopped(.watchdog)) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControllerError,
                .runtimeOperationFailed(
                    "launchd service state read failed label=\(RuntimeManagedService.watchdog.label) reason=launchctl denied"
                )
            )
        }
    }

    func testTimeoutPreservesLoadedStateAsFailure() {
        var currentTime = Date(timeIntervalSince1970: 0)
        let waiter = RuntimeServiceStopWaiter(
            serviceState: { _ in .loaded },
            now: { currentTime },
            sleep: { interval in
                currentTime = currentTime.addingTimeInterval(interval)
            },
            waitForVMProcessStoppedAfterServiceUnload: {},
            vmStopTimeoutSeconds: 10,
            serviceStopTimeoutSeconds: 1,
            pollIntervalSeconds: 0.5
        )

        XCTAssertThrowsError(try waiter.waitUntilStopped(.proxy)) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControllerError,
                .runtimeOperationFailed(
                    "service did not unload within 1s label=\(RuntimeManagedService.proxy.label)"
                )
            )
        }
    }

    func testVMWaitsForProcessAfterServiceUnload() throws {
        var processWaits = 0
        let waiter = RuntimeServiceStopWaiter(
            serviceState: { _ in .notLoaded },
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { _ in },
            waitForVMProcessStoppedAfterServiceUnload: {
                processWaits += 1
            },
            vmStopTimeoutSeconds: 10,
            serviceStopTimeoutSeconds: 3,
            pollIntervalSeconds: 0.5
        )

        try waiter.waitUntilStopped(.vm)

        XCTAssertEqual(processWaits, 1)
    }
}
