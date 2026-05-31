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
            RuntimeManagedService.guestLogSync,
            RuntimeManagedService.watchdog,
        ])
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { loaded.contains($0) },
            log: { _ in }
        )

        XCTAssertNoThrow(try controller.stopRuntimeServices())

        XCTAssertEqual(serviceManager.stoppedLabels, [
            RuntimeManagedService.watchdog.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.vm.label,
        ])
    }

    func testWaitsAfterEachLoadedServiceStops() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let loaded = Set([
            RuntimeManagedService.vm,
            RuntimeManagedService.proxy,
        ])
        var waitedLabels: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { loaded.contains($0) },
            waitUntilStopped: { waitedLabels.append($0.label) },
            log: { _ in }
        )

        try controller.stopRuntimeServices()

        XCTAssertEqual(serviceManager.stoppedLabels, [
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.vm.label,
        ])
        XCTAssertEqual(waitedLabels, [
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.vm.label,
        ])
    }

    func testPreparesLoadedServiceBeforeLaunchdStop() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let loaded = Set([RuntimeManagedService.vm])
        var events: [String] = []
        serviceManager.onStop = { events.append("stop:\($0.label)") }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { loaded.contains($0) },
            prepareForStop: { events.append("prepare:\($0.label)") },
            waitUntilStopped: { events.append("wait:\($0.label)") },
            log: { _ in }
        )

        try controller.stopRuntimeServices()

        XCTAssertEqual(events, [
            "prepare:\(RuntimeManagedService.vm.label)",
            "stop:\(RuntimeManagedService.vm.label)",
            "wait:\(RuntimeManagedService.vm.label)",
        ])
    }

    func testStopRuntimeServicesPropagatesPrepareFailureWithoutLaunchdStop() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { $0 == .vm },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("graceful stop failed") },
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices())
        XCTAssertEqual(serviceManager.stoppedLabels, [])
    }

    func testStopRuntimeServicesPropagatesWaitFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { $0 == .vm },
            waitUntilStopped: { _ in throw LauncherError.runtimeOperationFailed("still running") },
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices())
        XCTAssertEqual(serviceManager.stoppedLabels, [RuntimeManagedService.vm.label])
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
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
        ])
        XCTAssertEqual(serviceManager.startedPlists, [
            RuntimeManagedService.vm.launchDaemonPlist,
            RuntimeManagedService.guestLogSync.launchDaemonPlist,
            RuntimeManagedService.watchdog.launchDaemonPlist,
        ])
    }

    func testRestartOrStartStartsWhenServiceIsNotLoadedAfterRestart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { _ in false },
            log: { logs.append($0) }
        )

        controller.restartOrStartLaunchdService(.vm)

        XCTAssertEqual(serviceManager.restartedLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.startedLabels, [RuntimeManagedService.vm.label])
        XCTAssertTrue(logs.contains("launchd service not loaded after restart; starting label=\(RuntimeManagedService.vm.label)"))
    }

    func testRestartVMRuntimeServicesStopsVMWithPrepareAndStartsVMAndGuestLogSync() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set([RuntimeManagedService.vm, .guestLogSync])
        var events: [String] = []
        serviceManager.onStop = { service in
            events.append("stop:\(service.label)")
            loaded.remove(service)
        }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { loaded.contains($0) },
            prepareForStop: { events.append("prepare:\($0.label)") },
            waitUntilStopped: { events.append("wait:\($0.label)") },
            log: { _ in }
        )

        try controller.restartVMRuntimeServices()

        XCTAssertEqual(events, [
            "prepare:\(RuntimeManagedService.guestLogSync.label)",
            "stop:\(RuntimeManagedService.guestLogSync.label)",
            "wait:\(RuntimeManagedService.guestLogSync.label)",
            "prepare:\(RuntimeManagedService.vm.label)",
            "stop:\(RuntimeManagedService.vm.label)",
            "wait:\(RuntimeManagedService.vm.label)",
        ])
        XCTAssertEqual(serviceManager.startedLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.guestLogSync.label,
        ])
        XCTAssertEqual(serviceManager.restartedLabels, [])
    }

    func testRestartVMRuntimeServicesPropagatesPrepareFailureWithoutStart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { $0 == .vm },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("graceful stop failed") },
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.restartVMRuntimeServices())
        XCTAssertEqual(serviceManager.startedLabels, [])
        XCTAssertEqual(serviceManager.restartedLabels, [])
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
    var onStop: (RuntimeManagedService) -> Void = { _ in }

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
        onStop(service)
        stoppedLabels.append(service.label)
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        setEnabledLabels.append(service.label)
        return setEnabledResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
