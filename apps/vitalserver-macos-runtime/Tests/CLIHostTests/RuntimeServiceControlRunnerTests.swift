import Application
import Contracts
import Domain
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeServiceControlRunnerTests: XCTestCase {
    func testStartAllStartsServicesAndWaitsForHealth() throws {
        let harness = ServiceControlHarness()

        try harness.runner.run(.startAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services start requested",
            "status:recovering:start-services:runtime services start requested",
            "start:true:true:true",
            "wait:true:true:true",
            "status:healthy:start-services:runtime services started",
            "log:runtime services started",
        ])
    }

    func testRepairAllRestartsServicesAndWaitsForHealth() throws {
        let harness = ServiceControlHarness()

        try harness.runner.run(.repairAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services repair requested",
            "status:recovering:repair-services:runtime services repair requested",
            "stop",
            "start:true:true:true",
            "wait:true:true:true",
            "status:healthy:repair-services:runtime services repaired",
            "log:runtime services repaired",
        ])
    }

    func testRepairProxyStartsOnlyProxyAndWaitsForHealth() throws {
        let harness = ServiceControlHarness()

        try harness.runner.run(.repairProxy)

        XCTAssertEqual(harness.events, [
            "log:host proxy repair requested",
            "status:recovering:repair-proxy:host proxy repair requested",
            "start:false:true:false",
            "wait:false:true:false",
            "status:healthy:repair-proxy:host proxy repaired",
            "log:host proxy repaired",
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
            useCase: ControlRuntimeServicesUseCase(),
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
            waitForHealth: { policy in
                self.events.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
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
