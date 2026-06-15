import Application
import Contracts
import Domain
import XCTest

final class RuntimeVMStateControlUseCaseTests: XCTestCase {
    func testSettingsRestartPreparesGuestPoweroffBeforeStoppingHostServices() throws {
        let harness = RuntimeVMStateControlHarness()

        try harness.restartAfterSettingsApply()

        XCTAssertEqual(harness.events, [
            "log:runtime settings applied; preparing guest shutdown before restart",
            "status:recovering:configure:runtime settings applied; preparing guest shutdown before restart",
            "pid",
            "version",
            "prepare:0.1.13",
            "stop-after-poweroff:4242",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "wait-health:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "status:healthy:configure:runtime restarted after settings apply",
            "log:runtime restarted after settings apply",
            "clear",
        ])
    }

    func testSettingsRestartClearsGuestShutdownPreparationWhenPrepareFails() {
        let harness = RuntimeVMStateControlHarness()
        harness.prepareError = RuntimeVMStateControlTestError.prepareFailed

        XCTAssertThrowsError(try harness.restartAfterSettingsApply()) { error in
            XCTAssertEqual(error as? RuntimeVMStateControlTestError, .prepareFailed)
        }

        XCTAssertEqual(harness.events, [
            "log:runtime settings applied; preparing guest shutdown before restart",
            "status:recovering:configure:runtime settings applied; preparing guest shutdown before restart",
            "pid",
            "version",
            "prepare:0.1.13",
            "clear",
        ])
    }

    func testSettingsRestartForceStopsAndStartsWhenGuestShutdownWaitFails() throws {
        let harness = RuntimeVMStateControlHarness()
        harness.prepareError = RuntimeGuestUpdateUseCaseError.operationFailed("guest update shutdown timed out")

        try harness.restartAfterSettingsApply()

        XCTAssertEqual(harness.events, [
            "log:runtime settings applied; preparing guest shutdown before restart",
            "status:recovering:configure:runtime settings applied; preparing guest shutdown before restart",
            "pid",
            "version",
            "prepare:0.1.13",
            "log:settings restart guest shutdown failed; forcing VM runtime services stop before restart error=guest update shutdown timed out",
            "force-stop-runtime-services",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "wait-health:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "status:healthy:configure:runtime restarted after settings apply",
            "log:runtime restarted after settings apply",
            "clear",
        ])
    }

    func testSettingsRestartForceStopsAndStartsWhenPoweroffWaitFails() throws {
        let harness = RuntimeVMStateControlHarness()
        harness.stopAfterPoweroffError = StopRuntimeVMProcessUseCaseError.runtimeOperationFailed(
            "VM process did not stop within 900s"
        )

        try harness.restartAfterSettingsApply()

        XCTAssertEqual(harness.events, [
            "log:runtime settings applied; preparing guest shutdown before restart",
            "status:recovering:configure:runtime settings applied; preparing guest shutdown before restart",
            "pid",
            "version",
            "prepare:0.1.13",
            "stop-after-poweroff:4242",
            "log:settings restart guest shutdown failed; forcing VM runtime services stop before restart error=VM process did not stop within 900s",
            "force-stop-runtime-services",
            "start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "wait-health:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "status:healthy:configure:runtime restarted after settings apply",
            "log:runtime restarted after settings apply",
            "clear",
        ])
    }

    func testWatchdogRecoveryRestartsVMRuntimeThroughStateControlOwner() throws {
        let harness = RuntimeVMStateControlHarness()

        try harness.restartVMRuntimeForWatchdogRecovery()

        XCTAssertEqual(harness.events, [
            "log:watchdog requested VM runtime restart",
            "restart-vm-runtime",
            "log:watchdog dispatched VM runtime restart",
        ])
    }

    func testWatchdogRecoveryForceStopsAndRetriesWhenVMRuntimeRestartFailsDuringStop() throws {
        let harness = RuntimeVMStateControlHarness()
        harness.vmRuntimeRestartErrors = [
            StopRuntimeVMProcessUseCaseError.runtimeOperationFailed("timed out waiting for VM stop"),
        ]

        try harness.restartVMRuntimeForWatchdogRecovery()

        XCTAssertEqual(harness.events, [
            "log:watchdog requested VM runtime restart",
            "restart-vm-runtime",
            "log:watchdog VM runtime restart failed during graceful stop; forcing VM runtime services stop error=timed out waiting for VM stop",
            "force-stop-after-graceful-stop-failure",
            "restart-vm-runtime",
            "log:watchdog dispatched VM runtime restart",
        ])
    }

    func testWatchdogRecoveryForceStopsAndRetriesWhenLaunchdGracefulStopFails() throws {
        let harness = RuntimeVMStateControlHarness()
        harness.vmRuntimeRestartErrors = [
            RuntimeVMRuntimeRestartError.gracefulStopFailed(
                service: .vm,
                message: "launchd still owns VM process"
            ),
        ]

        try harness.restartVMRuntimeForWatchdogRecovery()

        XCTAssertEqual(harness.events, [
            "log:watchdog requested VM runtime restart",
            "restart-vm-runtime",
            "log:watchdog VM runtime restart failed during graceful stop; forcing VM runtime services stop error=graceful stop failed for ai.tirosh.vitalserver.helper.vm: launchd still owns VM process",
            "force-stop-after-graceful-stop-failure",
            "restart-vm-runtime",
            "log:watchdog dispatched VM runtime restart",
        ])
    }

    func testVMRuntimeRestartRejectsSettingsIntent() {
        let harness = RuntimeVMStateControlHarness()

        XCTAssertThrowsError(try harness.restartVMRuntimeWithSettingsIntent()) { error in
            XCTAssertEqual(
                error as? RuntimeVMStateControlError,
                .unsupportedIntent("restartAfterSettingsApply")
            )
        }

        XCTAssertTrue(harness.events.isEmpty)
    }

    func testServiceControlStartAndStopUseVMStateControlEntrypoints() throws {
        let harness = RuntimeVMStateControlHarness()

        try harness.startRuntimeServicesForServiceControl()
        try harness.stopRuntimeServicesForServiceControl()

        XCTAssertEqual(harness.events, [
            "service-control-start:ai.tirosh.vitalserver.helper.vm,ai.tirosh.vitalserver.helper.guest-log-sync,ai.tirosh.vitalserver.helper.proxy,ai.tirosh.vitalserver.helper.watchdog",
            "service-control-stop",
        ])
    }

    func testSingleVMServiceCommandsUseExplicitIntents() throws {
        let harness = RuntimeVMStateControlHarness()

        try harness.startVMServiceForGuestOperation()
        try harness.restartVMRuntimeForRepairOperation()

        XCTAssertEqual(harness.events, [
            "start-vm-service",
            "restart-vm-runtime",
        ])
    }

    func testUpdateShutdownStopCapturesVMPreparesGuestAndStopsAfterPoweroff() throws {
        let harness = RuntimeVMStateControlHarness()

        try harness.prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff()

        XCTAssertEqual(harness.events, [
            "pid",
            "log:captured VM process before guest update shutdown pid=4242",
            "prepare-update-shutdown:0.1.13",
            "stop-after-poweroff:4242",
            "clear",
        ])
    }

    func testUpdateShutdownStopClearsPreparationWhenPrepareFails() {
        let harness = RuntimeVMStateControlHarness()
        harness.prepareError = RuntimeVMStateControlTestError.prepareFailed

        XCTAssertThrowsError(try harness.prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff()) { error in
            XCTAssertEqual(error as? RuntimeVMStateControlTestError, .prepareFailed)
        }

        XCTAssertEqual(harness.events, [
            "pid",
            "log:captured VM process before guest update shutdown pid=4242",
            "prepare-update-shutdown:0.1.13",
            "clear",
        ])
    }

    func testUpdateShutdownStopForcesVMStopWhenGuestShutdownWaitFails() {
        let harness = RuntimeVMStateControlHarness()
        harness.prepareError = RuntimeGuestUpdateUseCaseError.operationFailed("guest update shutdown timed out")

        XCTAssertThrowsError(try harness.prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff()) { error in
            XCTAssertEqual(
                error as? RuntimeGuestUpdateUseCaseError,
                .operationFailed("guest update shutdown timed out")
            )
        }

        XCTAssertEqual(harness.events, [
            "pid",
            "log:captured VM process before guest update shutdown pid=4242",
            "prepare-update-shutdown:0.1.13",
            "log:guest update shutdown failed; forcing VM runtime services stop error=described:guest update shutdown timed out",
            "force-stop-runtime-services",
            "clear",
        ])
    }

    func testUpdateShutdownStopForcesVMStopWhenPoweroffStopFails() {
        let harness = RuntimeVMStateControlHarness()
        harness.stopAfterPoweroffError = RuntimeGuestUpdateUseCaseError.operationFailed("vm did not power off")

        XCTAssertThrowsError(try harness.prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff()) { error in
            XCTAssertEqual(
                error as? RuntimeGuestUpdateUseCaseError,
                .operationFailed("vm did not power off")
            )
        }

        XCTAssertEqual(harness.events, [
            "pid",
            "log:captured VM process before guest update shutdown pid=4242",
            "prepare-update-shutdown:0.1.13",
            "stop-after-poweroff:4242",
            "log:guest update shutdown failed; forcing VM runtime services stop error=described:vm did not power off",
            "force-stop-runtime-services",
            "clear",
        ])
    }

    func testUpdateShutdownStopForcesVMStopWhenStopTimeoutOccurs() {
        let harness = RuntimeVMStateControlHarness()
        harness.stopAfterPoweroffError = StopRuntimeVMProcessUseCaseError.runtimeOperationFailed(
            "VM process did not stop within 900s pid=4242 pidFile state=stop-timed-out: pid=4242 timeout-seconds=900"
        )

        XCTAssertThrowsError(try harness.prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff()) { error in
            XCTAssertEqual(
                error as? StopRuntimeVMProcessUseCaseError,
                .runtimeOperationFailed(
                    "VM process did not stop within 900s pid=4242 pidFile state=stop-timed-out: pid=4242 timeout-seconds=900"
                )
            )
        }

        XCTAssertEqual(harness.events, [
            "pid",
            "log:captured VM process before guest update shutdown pid=4242",
            "prepare-update-shutdown:0.1.13",
            "stop-after-poweroff:4242",
            "log:guest update shutdown failed; forcing VM runtime services stop error=described:VM process did not stop within 900s pid=4242 pidFile state=stop-timed-out: pid=4242 timeout-seconds=900",
            "force-stop-runtime-services",
            "clear",
        ])
    }

    func testVMDiskReplacementStopUsesGracefulStopWhenItSucceeds() throws {
        let harness = RuntimeVMStateControlHarness()

        try harness.stopRuntimeServicesForVMDiskReplacement()

        XCTAssertEqual(harness.events, [
            "stop-runtime-services",
        ])
    }

    func testVMDiskReplacementStopForcesVMStopWhenGracefulStopFails() throws {
        let harness = RuntimeVMStateControlHarness()
        harness.stopRuntimeServicesError = RuntimeVMStateControlTestError.stopFailed

        try harness.stopRuntimeServicesForVMDiskReplacement()

        XCTAssertEqual(harness.events, [
            "stop-runtime-services",
            "log:graceful runtime services stop failed before VM disk replacement; forcing VM process stop error=described:stopFailed",
            "force-stop-runtime-services",
            "log:runtime services stopped for VM disk replacement",
        ])
    }
}

private enum RuntimeVMStateControlTestError: Error, Equatable {
    case prepareFailed
    case stopFailed
}

private final class RuntimeVMStateControlHarness {
    var events: [String] = []
    var prepareError: Error?
    var stopRuntimeServicesError: Error?
    var stopAfterPoweroffError: Error?
    var vmRuntimeRestartErrors: [Error] = []

    func restartAfterSettingsApply() throws {
        try RuntimeVMStateControlUseCase().restart(
            intent: .restartAfterSettingsApply,
            operations: RuntimeVMStateControlOperations(
                runtimeVersion: {
                    self.events.append("version")
                    return "0.1.13"
                },
                runningVMProcessID: {
                    self.events.append("pid")
                    return 4242
                },
                prepareGuestShutdown: { version in
                    self.events.append("prepare:\(version)")
                    if let prepareError = self.prepareError {
                        throw prepareError
                    }
                },
                clearGuestShutdownPreparation: {
                    self.events.append("clear")
                },
                stopRuntimeServicesAfterGuestPoweroff: { pid in
                    self.events.append("stop-after-poweroff:\(pid)")
                    if let stopAfterPoweroffError = self.stopAfterPoweroffError {
                        throw stopAfterPoweroffError
                    }
                },
                forceStopRuntimeServicesAfterGuestShutdownFailure: {
                    self.events.append("force-stop-runtime-services")
                },
                startRuntimeServices: { policy in
                    self.events.append("start:\(serviceLabels(for: policy))")
                },
                waitForHealth: { policy in
                    self.events.append("wait-health:\(serviceLabels(for: policy))")
                },
                writeStatus: { status, operation, message in
                    self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
    }

    func restartVMRuntimeForWatchdogRecovery() throws {
        try RuntimeVMStateControlUseCase().restartVMRuntime(
            intent: .restartForWatchdogRecovery,
            operations: RuntimeVMRuntimeRestartOperations(
                restartVMRuntimeServices: {
                    self.events.append("restart-vm-runtime")
                    if !self.vmRuntimeRestartErrors.isEmpty {
                        throw self.vmRuntimeRestartErrors.removeFirst()
                    }
                },
                forceStopRuntimeServicesAfterGracefulStopFailure: {
                    self.events.append("force-stop-after-graceful-stop-failure")
                },
                describeError: { error in
                    "\(error)"
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
    }

    func restartVMRuntimeWithSettingsIntent() throws {
        try RuntimeVMStateControlUseCase().restartVMRuntime(
            intent: .restartAfterSettingsApply,
            operations: RuntimeVMRuntimeRestartOperations(
                restartVMRuntimeServices: {
                    self.events.append("restart-vm-runtime")
                    if !self.vmRuntimeRestartErrors.isEmpty {
                        throw self.vmRuntimeRestartErrors.removeFirst()
                    }
                },
                forceStopRuntimeServicesAfterGracefulStopFailure: {
                    self.events.append("force-stop-after-graceful-stop-failure")
                },
                describeError: { error in
                    "\(error)"
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
    }

    func startRuntimeServicesForServiceControl() throws {
        try RuntimeVMStateControlUseCase().startRuntimeServicesForServiceControl(
            RuntimeRequiredServicePolicy.allRuntimeServices,
            operations: serviceControlOperations
        )
    }

    func stopRuntimeServicesForServiceControl() throws {
        try RuntimeVMStateControlUseCase().stopRuntimeServicesForServiceControl(
            operations: serviceControlOperations
        )
    }

    private var serviceControlOperations: RuntimeVMServiceControlOperations {
        RuntimeVMServiceControlOperations(
            startRuntimeServices: { policy in
                self.events.append("service-control-start:\(serviceLabels(for: policy))")
            },
            stopRuntimeServices: {
                self.events.append("service-control-stop")
            }
        )
    }

    func startVMServiceForGuestOperation() throws {
        try RuntimeVMStateControlUseCase().startVMService(
            intent: .startForGuestOperation,
            operations: singleServiceOperations
        )
    }

    func restartVMRuntimeForRepairOperation() throws {
        try RuntimeVMStateControlUseCase().restartVMRuntimeForRepair(
            intent: .restartForRepairOperation,
            operations: singleServiceOperations
        )
    }

    private var singleServiceOperations: RuntimeVMSingleServiceOperations {
        RuntimeVMSingleServiceOperations(
            startVMService: {
                self.events.append("start-vm-service")
            },
            restartVMRuntimeServices: {
                self.events.append("restart-vm-runtime")
            }
        )
    }

    func prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff() throws {
        try RuntimeVMStateControlUseCase().prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff(
            manifest: updateManifest,
            operations: RuntimeVMUpdateShutdownOperations(
                runningVMProcessID: {
                    self.events.append("pid")
                    return 4242
                },
                prepareGuestShutdownForUpdate: { manifest in
                    self.events.append("prepare-update-shutdown:\(manifest.helperVersion)")
                    if let prepareError = self.prepareError {
                        throw prepareError
                    }
                },
                clearGuestShutdownPreparation: {
                    self.events.append("clear")
                },
                stopRuntimeServicesAfterGuestPoweroff: { pid in
                    self.events.append("stop-after-poweroff:\(pid)")
                    if let stopAfterPoweroffError = self.stopAfterPoweroffError {
                        throw stopAfterPoweroffError
                    }
                },
                forceStopRuntimeServicesAfterGuestShutdownFailure: {
                    self.events.append("force-stop-runtime-services")
                },
                describeError: { error in
                    "described:\(error)"
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
    }

    private var updateManifest: UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "0.1.13",
            releaseLabel: "0.1.13",
            targetPlatform: "macos-arm64",
            components: ["updater": "0.1.13"],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: [],
            migrations: []
        )
    }

    func stopRuntimeServicesForVMDiskReplacement() throws {
        try RuntimeVMStateControlUseCase().stopRuntimeServicesForVMDiskReplacement(
            operations: RuntimeVMDiskReplacementStopOperations(
                stopRuntimeServices: {
                    self.events.append("stop-runtime-services")
                    if let stopRuntimeServicesError = self.stopRuntimeServicesError {
                        throw stopRuntimeServicesError
                    }
                },
                forceStopRuntimeServicesAfterGracefulStopFailure: {
                    self.events.append("force-stop-runtime-services")
                },
                describeError: { error in
                    "described:\(error)"
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
    }
}

private func serviceLabels(for policy: RuntimeServiceRestartPolicy) -> String {
    RuntimeRequiredServicePolicy.requiredServices(for: policy)
        .map(\.label)
        .joined(separator: ",")
}
