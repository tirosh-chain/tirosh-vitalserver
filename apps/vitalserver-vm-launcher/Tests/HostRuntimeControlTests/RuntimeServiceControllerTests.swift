import RuntimeCore
@testable import HostRuntimeControl
import XCTest

final class RuntimeServiceControllerTests: XCTestCase {
    func testStopsLoadedRuntimeServicesInDependencyOrder() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let loaded = Set([
            Constants.Launchd.vmService,
            Constants.Launchd.proxyService,
            Constants.Launchd.watchdogService,
        ])
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { loaded.contains($0) },
            log: { _ in }
        )

        controller.stopRuntimeServices()

        XCTAssertEqual(serviceManager.stoppedLabels, [
            Constants.Launchd.watchdogService,
            Constants.Launchd.proxyService,
            Constants.Launchd.vmService,
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
            Constants.Launchd.vmService,
            Constants.Launchd.watchdogService,
        ])
        XCTAssertEqual(serviceManager.startedPlists, [
            "\(Constants.InstallPaths.launchDaemons)/\(Constants.Launchd.vmService).plist",
            "\(Constants.InstallPaths.launchDaemons)/\(Constants.Launchd.watchdogService).plist",
        ])
    }

    func testRestartFallsBackToStartWhenServiceIsNotLoadedAfterRestart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            isLoaded: { _ in false },
            log: { _ in }
        )

        controller.restartLaunchdService(Constants.Launchd.vmService)

        XCTAssertEqual(serviceManager.restartedLabels, [Constants.Launchd.vmService])
        XCTAssertEqual(serviceManager.startedLabels, [Constants.Launchd.vmService])
    }

    func testSetStartOnBootStopsAtFirstFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.setEnabledResults[Constants.Launchd.proxyService] = RuntimeProcessResult(
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
            Constants.Launchd.vmService,
            Constants.Launchd.proxyService,
        ])
    }
}

private final class ServiceControllerServiceManagerSpy: RuntimeServiceManager {
    var stoppedLabels: [String] = []
    var startedLabels: [String] = []
    var startedPlists: [String] = []
    var restartedLabels: [String] = []
    var setEnabledLabels: [String] = []
    var setEnabledResults: [String: RuntimeProcessResult] = [:]

    func state(label: String) -> String {
        "not-loaded"
    }

    func start(label: String, plist: String) {
        startedLabels.append(label)
        startedPlists.append(plist)
    }

    func restart(label: String) {
        restartedLabels.append(label)
    }

    func stop(label: String) {
        stoppedLabels.append(label)
    }

    func setEnabled(label: String, enabled: Bool) -> RuntimeProcessResult {
        setEnabledLabels.append(label)
        return setEnabledResults[label] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
