import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeServiceLifecycleWorkflowTests: XCTestCase {
    func testStartAllCompletesOnlyAfterRequiredServicesAreObservedLoaded() throws {
        let harness = RuntimeServiceLifecycleHarness()

        try harness.workflow.run(.startAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services start requested",
            "status:recovering:start-services:runtime services start requested",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "observe:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "status:recovering:start-services:runtime services start dispatched",
            "log:runtime services start dispatched",
        ])
    }

    func testStartAllDoesNotCompleteWhenRequiredServiceIsNotObservedLoaded() {
        let harness = RuntimeServiceLifecycleHarness()
        harness.startLeavesServiceNotLoaded = .guestLogSync

        XCTAssertThrowsError(try harness.workflow.run(.startAll)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd-service-not-loaded"))
            XCTAssertTrue(String(describing: error).contains(RuntimeManagedService.guestLogSync.label))
        }

        XCTAssertFalse(harness.events.contains("status:recovering:start-services:runtime services start dispatched"))
        XCTAssertFalse(harness.events.contains("log:runtime services start dispatched"))
    }

    func testRepairAllObservesStoppedStateBeforeStartingRequiredServices() throws {
        let harness = RuntimeServiceLifecycleHarness()
        harness.states = Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { ($0, .loaded) })

        try harness.workflow.run(.repairAll)

        XCTAssertEqual(Array(harness.events.prefix(5)), [
            "log:runtime services repair requested",
            "status:recovering:repair-services:runtime services repair requested",
            "stop",
            "observe:ai.tirosh.vitalserver.helper.watchdog,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.sleep-prevention",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
        ])
        XCTAssertTrue(harness.events.contains("status:recovering:repair-services:runtime services repair dispatched"))
    }

    func testStopAllCompletesOnlyAfterRuntimeServicesAreObservedStopped() throws {
        let harness = RuntimeServiceLifecycleHarness()
        harness.states = Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map { ($0, .loaded) })

        try harness.workflow.run(.stopAll)

        XCTAssertEqual(harness.events, [
            "log:runtime services stop requested",
            "stop",
            "observe:ai.tirosh.vitalserver.helper.watchdog,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.sleep-prevention",
            "status:degraded:stop-services:runtime services stopped",
            "log:runtime services stopped",
        ])
    }

    func testStopAllDoesNotCompleteWhenStoppedStateIsNotObserved() {
        let harness = RuntimeServiceLifecycleHarness()
        harness.stopLeavesServiceLoaded = .proxy

        XCTAssertThrowsError(try harness.workflow.run(.stopAll)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd-service-not-stopped"))
            XCTAssertTrue(String(describing: error).contains(RuntimeManagedService.proxy.label))
        }

        XCTAssertFalse(harness.events.contains("status:degraded:stop-services:runtime services stopped"))
        XCTAssertFalse(harness.events.contains("log:runtime services stopped"))
    }
}

private final class RuntimeServiceLifecycleHarness {
    var events: [String] = []
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]
    var startLeavesServiceNotLoaded: RuntimeManagedService?
    var stopLeavesServiceLoaded: RuntimeManagedService?

    var workflow: RuntimeServiceLifecycleWorkflow {
        RuntimeServiceLifecycleWorkflow(
            useCase: ControlRuntimeServicesUseCase(),
            effects: RuntimeServiceLifecycleEffects(
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
                }
            ),
            writer: RuntimeServiceLifecycleWriter(
                writeStatus: { level, operation, message in
                    self.events.append("status:\(level.rawValue):\(operation.rawValue):\(message)")
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
    }
}
