import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeServiceControllerTests: XCTestCase {
    func testStopsLoadedRuntimeServicesInDependencyOrder() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let loaded = Set([
            RuntimeManagedService.vm,
            RuntimeManagedService.proxy,
            RuntimeManagedService.watchdog,
        ])
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { loaded.contains($0) },
            log: { _ in }
        )

        controller.stopRuntimeServices()

        XCTAssertEqual(serviceManager.stoppedLabels, [
            RuntimeManagedService.watchdog.label,
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.vm.label,
        ])
    }

    func testStartsOnlyServicesRequestedByRestartPolicy() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { _ in false },
            log: { _ in }
        )

        controller.startRuntimeServices(RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: false,
            restartWatchdog: true
        ))

        XCTAssertEqual(serviceManager.startedLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.watchdog.label,
        ])
        XCTAssertEqual(serviceManager.startedPlists, [
            RuntimeManagedService.vm.launchDaemonPlist,
            RuntimeManagedService.watchdog.launchDaemonPlist,
        ])
    }

    func testRestartFallsBackToStartWhenServiceIsNotLoadedAfterRestart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { _ in false },
            log: { _ in }
        )

        controller.restartLaunchdService(.vm)

        XCTAssertEqual(serviceManager.restartedLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.startedLabels, [RuntimeManagedService.vm.label])
    }

    func testSetStartOnBootStopsAtFirstFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.setEnabledResults[.proxy] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "denied"
        )
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { _ in false },
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.setStartOnBoot(true))
        XCTAssertEqual(serviceManager.setEnabledLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.proxy.label,
        ])
    }
}

private final class ServiceControllerServiceManagerSpy: RuntimeServiceManager {
    var stoppedLabels: [String] = []
    var startedLabels: [String] = []
    var startedPlists: [String] = []
    var restartedLabels: [String] = []
    var setEnabledLabels: [String] = []
    var setEnabledResults: [RuntimeManagedService: RuntimeProcessResult] = [:]

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) {
        startedLabels.append(service.label)
        startedPlists.append(plist)
    }

    func restart(service: RuntimeManagedService) {
        restartedLabels.append(service.label)
    }

    func stop(service: RuntimeManagedService) {
        stoppedLabels.append(service.label)
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        setEnabledLabels.append(service.label)
        return setEnabledResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
