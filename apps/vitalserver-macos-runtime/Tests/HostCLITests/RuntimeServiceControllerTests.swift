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
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
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
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            waitUntilStopped: { waitedLabels.append($0.label) },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
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
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            prepareForStop: { events.append("prepare:\($0.label)") },
            waitUntilStopped: { events.append("wait:\($0.label)") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
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
            serviceState: { $0 == .vm ? .loaded : .notLoaded },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("graceful stop failed") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices())
        XCTAssertEqual(serviceManager.stoppedLabels, [])
    }

    func testStopRuntimeServicesBlocksWhenLaunchdStateReadFails() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .watchdog ? .readFailed("exitCode=1 stderr=permission") : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices()) { error in
            XCTAssertTrue(String(describing: error).contains("launchd service state read failed"))
        }
        XCTAssertEqual(serviceManager.stoppedLabels, [])
        XCTAssertTrue(logs.contains {
            $0.contains("launchd service state read failed label=\(RuntimeManagedService.watchdog.label)")
        })
    }

    func testStopRuntimeServicesPropagatesWaitFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .vm ? .loaded : .notLoaded },
            waitUntilStopped: { _ in throw LauncherError.runtimeOperationFailed("still running") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices())
        XCTAssertEqual(serviceManager.stoppedLabels, [RuntimeManagedService.vm.label])
    }

    func testDisableRuntimeServicesForUninstallDisablesStopOrderBeforeCleanup() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { _ in .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        try controller.disableRuntimeServicesForUninstall()

        XCTAssertEqual(serviceManager.setEnabledLabels, RuntimeManagedService.stopOrder.map(\.label))
        XCTAssertEqual(serviceManager.setEnabledValues, Array(repeating: false, count: RuntimeManagedService.stopOrder.count))
    }

    func testDisableRuntimeServicesForUninstallStopsAtFirstFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.setEnabledResults[.proxy] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "denied"
        )
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { _ in .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.disableRuntimeServicesForUninstall())
        XCTAssertEqual(serviceManager.setEnabledLabels, [
            RuntimeManagedService.watchdog.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.proxy.label,
        ])
    }

    func testStartsOnlyServicesRequestedByRestartPolicy() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set<RuntimeManagedService>()
        serviceManager.onStart = { loaded.insert($0) }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertNoThrow(try controller.startRuntimeServices(RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: true
        )))

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
        XCTAssertEqual(serviceManager.setEnabledLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
        ])
        XCTAssertEqual(serviceManager.setEnabledValues, [true, true, true])
    }

    func testStartsGuestLogSyncWhenOnlyGuestLogSyncIsRequestedByRestartPolicy() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set<RuntimeManagedService>()
        serviceManager.onStart = { loaded.insert($0) }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertNoThrow(try controller.startRuntimeServices(RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        )))

        XCTAssertEqual(serviceManager.startedLabels, [
            RuntimeManagedService.guestLogSync.label,
        ])
        XCTAssertEqual(serviceManager.startedPlists, [
            RuntimeManagedService.guestLogSync.launchDaemonPlist,
        ])
        XCTAssertEqual(serviceManager.setEnabledLabels, [
            RuntimeManagedService.guestLogSync.label,
        ])
        XCTAssertEqual(serviceManager.setEnabledValues, [true])
    }

    func testStartRuntimeServicesFailsWhenLaunchdServiceDoesNotLoad() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { _ in .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try controller.startRuntimeServices(RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("launchd service failed to load"))
        }
        XCTAssertEqual(serviceManager.startedLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.setEnabledLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.setEnabledValues, [true])
        XCTAssertTrue(logs.contains {
            $0.contains("launchd service failed to load label=\(RuntimeManagedService.vm.label)")
        })
    }

    func testStartRuntimeServicesFailsBeforeBootstrapWhenEnableFails() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.setEnabledResults[.vm] = RuntimeProcessResult(
            exitCode: 125,
            stdout: "",
            stderr: "Service is disabled"
        )
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { _ in .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try controller.startRuntimeServices(RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("launchctl enable"))
        }
        XCTAssertEqual(serviceManager.setEnabledLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.setEnabledValues, [true])
        XCTAssertEqual(serviceManager.startedLabels, [])
        XCTAssertTrue(logs.contains {
            $0.contains("command stderr executable=\(Constants.Commands.launchctl) stderr=Service is disabled")
        })
    }

    func testRestartOrStartStartsWhenServiceIsNotLoadedAfterRestart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set<RuntimeManagedService>()
        serviceManager.onStart = { loaded.insert($0) }
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertNoThrow(try controller.restartOrStartLaunchdService(.vm))

        XCTAssertEqual(serviceManager.restartedLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.startedLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.setEnabledLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(serviceManager.setEnabledValues, [true])
        XCTAssertTrue(logs.contains("launchd service not loaded after restart; starting label=\(RuntimeManagedService.vm.label)"))
    }

    func testRestartVMRuntimeServicesStopsVMWithPrepareAndStartsVMAndGuestLogSync() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set([RuntimeManagedService.vm, .guestLogSync])
        var events: [String] = []
        serviceManager.onStart = { loaded.insert($0) }
        serviceManager.onStop = { service in
            events.append("stop:\(service.label)")
            loaded.remove(service)
        }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            prepareForStop: { events.append("prepare:\($0.label)") },
            waitUntilStopped: { events.append("wait:\($0.label)") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
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
        XCTAssertEqual(serviceManager.setEnabledLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.guestLogSync.label,
        ])
        XCTAssertEqual(serviceManager.setEnabledValues, [true, true])
        XCTAssertEqual(serviceManager.restartedLabels, [])
    }

    func testRestartVMRuntimeServicesPropagatesPrepareFailureWithoutStart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .vm ? .loaded : .notLoaded },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("graceful stop failed") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.restartVMRuntimeServices())
        XCTAssertEqual(serviceManager.startedLabels, [])
        XCTAssertEqual(serviceManager.restartedLabels, [])
    }

    func testStopRuntimeServicesAfterGuestPoweroffWaitsForVMExitBeforeUnloadingVM() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set([
            RuntimeManagedService.watchdog,
            .proxy,
            .guestLogSync,
            .vm,
            .sleepPrevention,
        ])
        var events: [String] = []
        serviceManager.onStop = { service in
            events.append("stop:\(service.label)")
            loaded.remove(service)
        }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            prepareForStop: { events.append("prepare:\($0.label)") },
            waitUntilStopped: { events.append("wait:\($0.label)") },
            waitForVMProcessExitAfterGuestPoweroff: { pid in
                events.append("wait-vm-process:\(pid)")
            },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        try controller.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: 123)

        XCTAssertEqual(events, [
            "prepare:\(RuntimeManagedService.watchdog.label)",
            "stop:\(RuntimeManagedService.watchdog.label)",
            "wait:\(RuntimeManagedService.watchdog.label)",
            "prepare:\(RuntimeManagedService.proxy.label)",
            "stop:\(RuntimeManagedService.proxy.label)",
            "wait:\(RuntimeManagedService.proxy.label)",
            "wait-vm-process:123",
            "prepare:\(RuntimeManagedService.guestLogSync.label)",
            "stop:\(RuntimeManagedService.guestLogSync.label)",
            "wait:\(RuntimeManagedService.guestLogSync.label)",
            "stop:\(RuntimeManagedService.vm.label)",
            "wait:\(RuntimeManagedService.vm.label)",
            "prepare:\(RuntimeManagedService.sleepPrevention.label)",
            "stop:\(RuntimeManagedService.sleepPrevention.label)",
            "wait:\(RuntimeManagedService.sleepPrevention.label)",
        ])
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
            serviceState: { _ in .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
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
    var setEnabledValues: [Bool] = []
    var setEnabledResults: [RuntimeManagedService: RuntimeProcessResult] = [:]
    var onStart: (RuntimeManagedService) -> Void = { _ in }
    var onStop: (RuntimeManagedService) -> Void = { _ in }

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) {
        onStart(service)
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
        setEnabledValues.append(enabled)
        return setEnabledResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
