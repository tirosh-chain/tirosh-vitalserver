import Application
import Contracts
import Domain
import XCTest

final class ControlRuntimeServicesUseCaseTests: XCTestCase {
    func testPlanOwnsServiceControlOperationIntentAndCompletionServices() {
        let harness = ControlRuntimeServicesUseCaseHarness()

        let repair = harness.useCase.plan(.repairAll)
        let start = harness.useCase.plan(.startAll)
        let stop = harness.useCase.plan(.stopAll)

        XCTAssertEqual(repair.operation, .repairServices)
        XCTAssertEqual(repair.startPolicy, RuntimeRequiredServicePolicy.allRuntimeServices)
        XCTAssertEqual(repair.stopServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(repair.requiredStartedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(repair.requiredStoppedServices, RuntimeManagedService.stopOrder)

        XCTAssertEqual(start.operation, .startServices)
        XCTAssertEqual(start.startPolicy, RuntimeRequiredServicePolicy.allRuntimeServices)
        XCTAssertEqual(start.stopServices, [])
        XCTAssertEqual(start.requiredStartedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(start.requiredStoppedServices, [])

        XCTAssertEqual(stop.operation, .stopServices)
        XCTAssertNil(stop.startPolicy)
        XCTAssertEqual(stop.stopServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(stop.requiredStartedServices, [])
        XCTAssertEqual(stop.requiredStoppedServices, RuntimeManagedService.stopOrder)
    }

    func testStartRequiredServicesExecutesPortAndReturnsExplicitObservation() throws {
        let harness = ControlRuntimeServicesUseCaseHarness()
        let policy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        )

        let observation = try harness.useCase.startRequiredServices(policy)

        XCTAssertEqual(harness.events, [
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync",
            "observe:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync",
        ])
        XCTAssertEqual(observation.states[.vm], .loaded)
        XCTAssertEqual(observation.states[.guestLogSync], .loaded)
    }

    func testStopRuntimeServicesReturnsExplicitObservationForRequestedServices() throws {
        let harness = ControlRuntimeServicesUseCaseHarness()

        let observation = try harness.useCase.stopRuntimeServices(observing: [.proxy, .watchdog])

        XCTAssertEqual(harness.events, [
            "stop",
            "observe:ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
        ])
        XCTAssertEqual(observation.states[.proxy], .notLoaded)
        XCTAssertEqual(observation.states[.watchdog], .notLoaded)
    }
}

private final class ControlRuntimeServicesUseCaseHarness {
    var events: [String] = []
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]

    var useCase: ControlRuntimeServicesUseCase {
        ControlRuntimeServicesUseCase(
            ports: RuntimeServiceControlPorts(
                startRuntimeServices: { policy in
                    let services = RuntimeRequiredServicePolicy.requiredServices(for: policy)
                    self.events.append("start:\(services.map(\.label).joined(separator: ","))")
                    for service in services {
                        self.states[service] = .loaded
                    }
                },
                stopRuntimeServices: {
                    self.events.append("stop")
                    for service in RuntimeManagedService.stopOrder {
                        self.states[service] = .notLoaded
                    }
                },
                serviceStates: { services in
                    self.events.append("observe:\(services.map(\.label).joined(separator: ","))")
                    return Dictionary(uniqueKeysWithValues: services.map { service in
                        (service, self.states[service] ?? .notLoaded)
                    })
                }
            )
        )
    }
}
