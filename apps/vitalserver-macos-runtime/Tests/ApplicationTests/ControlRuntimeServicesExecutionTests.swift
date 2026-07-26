import Application
import Contracts
import Domain
import XCTest
import Errors

final class ControlRuntimeServicesExecutionTests: XCTestCase {
    func testStartAllCompletesOnlyAfterRequiredServicesAreObservedLoaded() throws {
        let harness = RuntimeServiceLifecycleHarness()

        try harness.run(.startAll)

        XCTAssertEqual(harness.events, [
            "log:host runtime services start requested",
            "status:recovering:start-services:host runtime services start requested",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "observe:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "wait-health:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "status:healthy:start-services:host runtime services started",
            "log:host runtime services started",
        ])
    }

    func testStartAllDoesNotCompleteWhenRequiredServiceIsNotObservedLoaded() {
        let harness = RuntimeServiceLifecycleHarness()
        harness.startLeavesServiceNotLoaded = .guestLogSync

        XCTAssertThrowsError(try harness.run(.startAll)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd-service-not-loaded"))
            XCTAssertTrue(String(describing: error).contains(RuntimeManagedService.guestLogSync.label))
        }

        XCTAssertFalse(harness.events.contains("status:healthy:start-services:host runtime services started"))
        XCTAssertFalse(harness.events.contains("log:host runtime services started"))
    }

    func testRepairAllObservesStoppedStateBeforeStartingRequiredServices() throws {
        let harness = RuntimeServiceLifecycleHarness()
        harness.states = Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { ($0, .loaded) })

        try harness.run(.repairAll)

        XCTAssertEqual(Array(harness.events.prefix(7)), [
            "log:host runtime services repair requested",
            "status:recovering:repair-services:host runtime services repair requested",
            "stop",
            "observe:ai.tirosh.vitalserver.helper.watchdog,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.sleep-prevention",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "observe:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "wait-health:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
        ])
        XCTAssertTrue(harness.events.contains("status:healthy:repair-services:host runtime services repaired"))
    }

    func testRepairProxyStartsOnlyProxyAndObservesProxyLoaded() throws {
        let harness = RuntimeServiceLifecycleHarness()

        try harness.run(.repairProxy)

        XCTAssertEqual(harness.events, [
            "log:host proxy repair requested",
            "status:recovering:repair-proxy:host proxy repair requested",
            "start:ai.tirosh.vitalserver.helper.proxy",
            "observe:ai.tirosh.vitalserver.helper.proxy",
            "wait-health:ai.tirosh.vitalserver.helper.proxy",
            "status:healthy:repair-proxy:host proxy repaired",
            "log:host proxy repaired",
        ])
    }

    func testRepairProxyDoesNotCompleteWhenProxyIsNotObservedLoaded() {
        let harness = RuntimeServiceLifecycleHarness()
        harness.startLeavesServiceNotLoaded = .proxy

        XCTAssertThrowsError(try harness.run(.repairProxy)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd-service-not-loaded"))
            XCTAssertTrue(String(describing: error).contains(RuntimeManagedService.proxy.label))
        }

        XCTAssertFalse(harness.events.contains("status:healthy:repair-proxy:host proxy repaired"))
        XCTAssertFalse(harness.events.contains("log:host proxy repaired"))
    }

    func testRepairAllDoesNotCompleteWhenHealthWaitFails() {
        let harness = RuntimeServiceLifecycleHarness()
        harness.healthWaitError = TestRuntimeServiceLifecycleError.health

        XCTAssertThrowsError(try harness.run(.repairAll)) { error in
            XCTAssertEqual(error as? TestRuntimeServiceLifecycleError, .health)
        }

        XCTAssertTrue(harness.events.contains("wait-health:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog"))
        XCTAssertFalse(harness.events.contains("status:healthy:repair-services:host runtime services repaired"))
        XCTAssertFalse(harness.events.contains("log:host runtime services repaired"))
    }

    func testStopAllCompletesOnlyAfterRuntimeServicesAreObservedStopped() throws {
        let harness = RuntimeServiceLifecycleHarness()
        harness.states = Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { ($0, .loaded) })

        try harness.run(.stopAll)

        XCTAssertEqual(harness.events, [
            "log:host runtime services stop requested",
            "stop",
            "observe:ai.tirosh.vitalserver.helper.watchdog,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.sleep-prevention",
            "status:degraded:stop-services:host runtime services stopped",
            "log:host runtime services stopped",
        ])
    }

    func testStopAllDoesNotCompleteWhenStoppedStateIsNotObserved() {
        let harness = RuntimeServiceLifecycleHarness()
        harness.stopLeavesServiceLoaded = .proxy

        XCTAssertThrowsError(try harness.run(.stopAll)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd-service-not-stopped"))
            XCTAssertTrue(String(describing: error).contains(RuntimeManagedService.proxy.label))
        }

        XCTAssertFalse(harness.events.contains("status:degraded:stop-services:host runtime services stopped"))
        XCTAssertFalse(harness.events.contains("log:host runtime services stopped"))
    }
}

private enum TestRuntimeServiceLifecycleError: Error {
    case health
}

private final class RuntimeServiceLifecycleHarness {
    var events: [String] = []
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]
    var startLeavesServiceNotLoaded: RuntimeManagedService?
    var stopLeavesServiceLoaded: RuntimeManagedService?
    var healthWaitError: Error?

    func run(_ request: RuntimeServiceControlRequest) throws {
        try ControlRuntimeServicesUseCase().run(request, operations: operations)
    }

    var operations: RuntimeServiceControlOperations {
        RuntimeServiceControlOperations(
            startRuntimeServices: { policy in
                let services = RuntimeRequiredServicePolicy.requiredServices(for: policy)
                self.events.append("start:\(services.map(\.label).joined(separator: ","))")
                for service in services {
                    self.states[service] = service == self.startLeavesServiceNotLoaded ? .notLoaded : .loaded
                }
            },
            stopRuntimeServices: {
                self.events.append("stop")
                for service in RuntimeManagedService.stopOrder {
                    self.states[service] = service == self.stopLeavesServiceLoaded ? .loaded : .notLoaded
                }
            },
            serviceStates: { services in
                self.events.append("observe:\(services.map(\.label).joined(separator: ","))")
                return Dictionary(uniqueKeysWithValues: services.map { service in
                    (service, self.states[service] ?? .notLoaded)
                })
            },
            waitForHealth: { policy in
                let services = RuntimeRequiredServicePolicy.requiredServices(for: policy)
                self.events.append("wait-health:\(services.map(\.label).joined(separator: ","))")
                if let healthWaitError = self.healthWaitError {
                    throw healthWaitError
                }
            },
            writeStatus: { level, operation, message in
                self.events.append("status:\(level.rawValue):\(operation.rawValue):\(message)")
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }
}
