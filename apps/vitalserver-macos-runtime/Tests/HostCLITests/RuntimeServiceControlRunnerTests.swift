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

    func testRepairAllRestartsServicesWithoutWaitingForHealth() throws {
        let harness = ServiceControlHarness()

        try harness.runner.run(.repairAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services repair requested",
            "status:recovering:repair-services:runtime services repair requested",
            "stop",
            "start:true:true:true",
            "status:recovering:repair-services:runtime services repair dispatched",
            "log:runtime services repair dispatched",
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
    var serviceStates: [RuntimeManagedService: RuntimeServiceState] = [:]

    var runner: RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: { policy in
                self.events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                if let startError = self.startError {
                    throw startError
                }
                for service in RuntimeRequiredServicePolicy.requiredServices(for: policy) {
                    self.serviceStates[service] = .loaded
                }
            },
            stopRuntimeServices: {
                self.events.append("stop")
                for service in RuntimeManagedService.stopOrder {
                    self.serviceStates[service] = .notLoaded
                }
            },
            serviceStates: { services in
                Dictionary(uniqueKeysWithValues: services.map { service in
                    (service, self.serviceStates[service] ?? .notLoaded)
                })
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
