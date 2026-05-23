import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeServiceControlRunnerTests: XCTestCase {
    func testStartAllStartsServicesWithoutWaitingForHealth() throws {
        let harness = ServiceControlHarness()

        try harness.runner.run(.startAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services start requested",
            "status:recovering:start-services:runtime services start requested",
            "start:true:true:true",
            "status:recovering:start-services:runtime services start dispatched",
            "log:runtime services start dispatched",
        ])
    }

    func testStopAllStopsServicesAndWritesDegradedStatus() throws {
        let harness = ServiceControlHarness()

        try harness.runner.run(.stopAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services stop requested",
            "stop",
            "status:degraded:stop-services:runtime services stopped",
            "log:runtime services stopped",
        ])
    }

    func testStartAllStopsBeforeHealthyStatusWhenStartFails() {
        let harness = ServiceControlHarness()
        harness.startError = TestServiceControlError.start

        XCTAssertThrowsError(try harness.runner.run(.startAll))

        XCTAssertEqual(harness.events, [
            "log:runtime services start requested",
            "status:recovering:start-services:runtime services start requested",
            "start:true:true:true",
        ])
    }
}

private final class ServiceControlHarness {
    var events: [String] = []
    var startError: Error?

    var runner: RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: { policy in
                self.events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                if let startError = self.startError {
                    throw startError
                }
            },
            stopRuntimeServices: {
                self.events.append("stop")
            },
            writeStatus: { status, operation, message in
                self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }
}

private enum TestServiceControlError: Error {
    case start
}
