import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeServiceControllerTests: XCTestCase {
    func testStopsLoadedRuntimeServicesInDependencyOrder() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let loaded = Set([
            RuntimeManagedService.platformAgent,
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

    func testUnloadsVMWithoutPreStopSignalSoLaunchdCannotRelaunchIt() throws {
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
            "stop:\(RuntimeManagedService.vm.label)",
            "wait:\(RuntimeManagedService.vm.label)",
        ])
    }

    func testPreparesLoadedNonVMServiceBeforeLaunchdStop() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let loaded = Set([RuntimeManagedService.proxy])
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
            "prepare:\(RuntimeManagedService.proxy.label)",
            "stop:\(RuntimeManagedService.proxy.label)",
            "wait:\(RuntimeManagedService.proxy.label)",
        ])
    }

    func testStopRuntimeServicesPropagatesPrepareFailureForNonVMServiceWithoutLaunchdStop() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .proxy ? .loaded : .notLoaded },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("graceful stop failed") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices())
        XCTAssertEqual(serviceManager.stoppedLabels, [])
    }

    func testStopRuntimeServicesDoesNotInvokeVMPrepareHookBeforeLaunchdUnload() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set([RuntimeManagedService.vm])
        serviceManager.onStop = { loaded.remove($0) }
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { loaded.contains($0) ? .loaded : .notLoaded },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("VM graceful stop failed") },
            waitUntilStopped: { _ in },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        try controller.stopRuntimeServices()

        XCTAssertEqual(serviceManager.stoppedLabels, [RuntimeManagedService.vm.label])
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

    func testStopRuntimeServicesPropagatesBootoutCommandFailureBeforeWait() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.stopResults[.vm] = RuntimeProcessResult(
            exitCode: 5,
            stdout: "",
            stderr: "bootout failed"
        )
        var waitedLabels: [String] = []
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .vm ? .loaded : .notLoaded },
            waitUntilStopped: { waitedLabels.append($0.label) },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServices()) { error in
            XCTAssertTrue(String(describing: error).contains("launchd command failed action=bootout"))
        }
        XCTAssertEqual(serviceManager.stoppedLabels, [RuntimeManagedService.vm.label])
        XCTAssertEqual(waitedLabels, [])
        XCTAssertTrue(logs.contains {
            $0.contains("command stderr executable=\(Constants.Commands.launchctl) stderr=bootout failed")
        })
    }

    func testStopLaunchdServicePropagatesStateReadFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .sleepPrevention ? .readFailed("launchctl denied") : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopLaunchdService(.sleepPrevention)) { error in
            XCTAssertTrue(String(describing: error).contains(
                "launchd service state read failed label=\(RuntimeManagedService.sleepPrevention.label)"
            ))
        }
        XCTAssertEqual(serviceManager.stoppedLabels, [])
    }

    func testStopLaunchdServicePropagatesBootoutFailure() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.stopResults[.sleepPrevention] = RuntimeProcessResult(
            exitCode: 5,
            stdout: "",
            stderr: "bootout denied"
        )
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .sleepPrevention ? .loaded : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try controller.stopLaunchdService(.sleepPrevention)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd command failed action=bootout"))
        }
        XCTAssertEqual(serviceManager.stoppedLabels, [RuntimeManagedService.sleepPrevention.label])
        XCTAssertTrue(logs.contains {
            $0.contains("command stderr executable=\(Constants.Commands.launchctl) stderr=bootout denied")
        })
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

        XCTAssertEqual(serviceManager.setEnabledLabels, RuntimeManagedService.uninstallOrder.map(\.label))
        XCTAssertEqual(serviceManager.setEnabledValues, Array(repeating: false, count: RuntimeManagedService.uninstallOrder.count))
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

    func testClearDisabledOverridesAfterUninstallEnablesStopOrderBeforeCompletion() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { _ in .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        try controller.clearDisabledOverridesAfterUninstall()

        XCTAssertEqual(serviceManager.setEnabledLabels, RuntimeManagedService.uninstallOrder.map(\.label))
        XCTAssertEqual(serviceManager.setEnabledValues, Array(repeating: true, count: RuntimeManagedService.uninstallOrder.count))
    }

    func testClearDisabledOverridesAfterUninstallStopsAtFirstFailure() {
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

        XCTAssertThrowsError(try controller.clearDisabledOverridesAfterUninstall())
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

    func testStartsWatchdogBeforeProxyWhenAllRuntimeServicesAreRequested() {
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

        XCTAssertNoThrow(try controller.startRuntimeServices(RuntimeRequiredServicePolicy.allRuntimeServices))

        XCTAssertEqual(serviceManager.startedLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
            RuntimeManagedService.proxy.label,
        ])
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

    func testStartRuntimeServicesPropagatesBootstrapCommandFailureBeforeStateFallback() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.startResults[.vm] = RuntimeProcessResult(
            exitCode: 5,
            stdout: "",
            stderr: "bootstrap failed"
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
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("launchd command failed action=bootstrap"))
        }
        XCTAssertEqual(serviceManager.startedLabels, [RuntimeManagedService.vm.label])
        XCTAssertTrue(logs.contains {
            $0.contains("command stderr executable=\(Constants.Commands.launchctl) stderr=bootstrap failed")
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
            XCTAssertEqual(
                error as? RuntimeServiceControllerError,
                .runtimeOperationFailed(
                    "launchd command failed action=enable label=\(RuntimeManagedService.vm.label) exitCode=125"
                )
            )
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

    func testRestartOrStartPropagatesRestartFailureWhenServiceRemainsLoaded() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        serviceManager.restartResults[.proxy] = RuntimeProcessResult(
            exitCode: 5,
            stdout: "",
            stderr: "kickstart failed"
        )
        var logs: [String] = []
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .proxy ? .loaded : .notLoaded },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try controller.restartOrStartLaunchdService(.proxy)) { error in
            XCTAssertTrue(String(describing: error).contains("launchd command failed action=kickstart"))
        }
        XCTAssertEqual(serviceManager.restartedLabels, [RuntimeManagedService.proxy.label])
        XCTAssertEqual(serviceManager.startedLabels, [])
        XCTAssertTrue(logs.contains {
            $0.contains("command stderr executable=\(Constants.Commands.launchctl) stderr=kickstart failed")
        })
    }

    func testRestartVMRuntimeServicesUnloadsVMBeforeStartingVMAndGuestLogSync() throws {
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

    func testRestartVMRuntimeServicesWrapsGuestLogSyncGracefulStopFailureWithoutStart() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { $0 == .guestLogSync ? .loaded : .notLoaded },
            prepareForStop: { _ in throw LauncherError.runtimeOperationFailed("graceful stop failed") },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.restartVMRuntimeServices()) { error in
            XCTAssertEqual(
                error as? RuntimeVMRuntimeRestartError,
                .gracefulStopFailed(
                    service: .guestLogSync,
                    message: "graceful stop failed"
                )
            )
        }
        XCTAssertEqual(serviceManager.startedLabels, [])
        XCTAssertEqual(serviceManager.restartedLabels, [])
    }

    func testStopRuntimeServicesAfterGuestPoweroffUnloadsVMBeforeStoppingGuestLogSync() throws {
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
            "stop:\(RuntimeManagedService.vm.label)",
            "wait:\(RuntimeManagedService.vm.label)",
            "prepare:\(RuntimeManagedService.guestLogSync.label)",
            "stop:\(RuntimeManagedService.guestLogSync.label)",
            "wait:\(RuntimeManagedService.guestLogSync.label)",
            "prepare:\(RuntimeManagedService.sleepPrevention.label)",
            "stop:\(RuntimeManagedService.sleepPrevention.label)",
            "wait:\(RuntimeManagedService.sleepPrevention.label)",
        ])
    }

    func testStopRuntimeServicesAfterGuestPoweroffDoesNotWaitForCapturedPIDWhileLaunchdOwnsVM() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set([
            RuntimeManagedService.vm,
            .guestLogSync,
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
                XCTFail("VM pid \(pid) must not be waited while launchd VM service is still loaded")
                throw LauncherError.runtimeOperationFailed("launchd still owns VM process")
            },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        try controller.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: 123)

        XCTAssertEqual(events, [
            "stop:\(RuntimeManagedService.vm.label)",
            "wait:\(RuntimeManagedService.vm.label)",
            "prepare:\(RuntimeManagedService.guestLogSync.label)",
            "stop:\(RuntimeManagedService.guestLogSync.label)",
            "wait:\(RuntimeManagedService.guestLogSync.label)",
        ])
    }

    func testStopRuntimeServicesAfterGuestPoweroffPropagatesVMStateReadFailureWithoutPIDFallback() {
        let serviceManager = ServiceControllerServiceManagerSpy()
        let controller = RuntimeServiceController(
            serviceManager: serviceManager,
            serviceState: { service in
                service == .vm ? .readFailed("launchctl denied") : .notLoaded
            },
            waitForVMProcessExitAfterGuestPoweroff: { pid in
                XCTFail("VM pid \(pid) must not be waited when launchd VM state read fails")
            },
            launchDaemonPlist: { $0.launchDaemonPlist },
            launchctlPath: Constants.Commands.launchctl,
            log: { _ in }
        )

        XCTAssertThrowsError(try controller.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: 123)) { error in
            XCTAssertTrue(String(describing: error).contains(
                "launchd service state read failed label=\(RuntimeManagedService.vm.label)"
            ))
        }
        XCTAssertEqual(serviceManager.stoppedLabels, [])
    }

    func testStopRuntimeServicesAfterGuestPoweroffWaitsForCapturedVMProcessWhenVMServiceAlreadyUnloaded() throws {
        let serviceManager = ServiceControllerServiceManagerSpy()
        var loaded = Set([
            RuntimeManagedService.watchdog,
            .proxy,
            .guestLogSync,
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
            RuntimeManagedService.platformAgent.label,
            RuntimeManagedService.vm.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
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
    var startResults: [RuntimeManagedService: RuntimeProcessResult] = [:]
    var restartResults: [RuntimeManagedService: RuntimeProcessResult] = [:]
    var stopResults: [RuntimeManagedService: RuntimeProcessResult] = [:]
    var setEnabledResults: [RuntimeManagedService: RuntimeProcessResult] = [:]
    var onStart: (RuntimeManagedService) -> Void = { _ in }
    var onStop: (RuntimeManagedService) -> Void = { _ in }

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        onStart(service)
        startedLabels.append(service.label)
        startedPlists.append(plist)
        return startResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        restartedLabels.append(service.label)
        return restartResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        onStop(service)
        stoppedLabels.append(service.label)
        return stopResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        setEnabledLabels.append(service.label)
        setEnabledValues.append(enabled)
        return setEnabledResults[service] ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
