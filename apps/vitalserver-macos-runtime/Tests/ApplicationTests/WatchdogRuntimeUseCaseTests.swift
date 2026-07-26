import Application
import Contracts
import Domain
import Foundation
import XCTest

final class WatchdogRuntimeUseCaseTests: XCTestCase {
    func testActiveOperationSkipPlanPreservesOperationExplicitly() {
        let useCase = WatchdogRuntimeUseCase()

        let plan = useCase.activeOperationSkipPlan(.applyBundle)

        XCTAssertEqual(
            plan.logMessage,
            "watchdog skipped during active runtime operation operation=apply-bundle"
        )
        XCTAssertEqual(plan.lifecycleMessage, plan.logMessage)
        XCTAssertEqual(plan.eventType, .watchdogSkipped)
        XCTAssertEqual(plan.printMessage, "watchdog: skipped active operation")
    }

    func testInitialSnapshotDecisionSuppressesRecoveryForProtectedStorageFailureWithoutProbe() {
        let useCase = WatchdogRuntimeUseCase()

        let decision = useCase.initialSnapshotDecision(healthSnapshot(
            vmErrors: [.guestFilesystemReadOnly],
            guestHTTP: "failed",
            failureReasons: [.guestFilesystemReadOnly, .guestHTTP("failed")]
        ))

        guard case .recoverySuppressed(let plan) = decision else {
            return XCTFail("expected suppressed recovery decision")
        }
        XCTAssertEqual(plan.status, .critical)
        XCTAssertEqual(
            plan.message,
            "watchdog recovery suppressed: guest-filesystem-read-only; action=backup-and-recreate-vm"
        )
        XCTAssertEqual(plan.eventType, .recoverySuppressed)
        XCTAssertEqual(plan.printMessage, "watchdog: suppressed")
    }

    func testRecoveryDecisionPlansDisabledRecoveryWithoutRestartCommands() {
        let useCase = WatchdogRuntimeUseCase()

        let decision = useCase.recoveryDecision(
            snapshot: healthSnapshot(guestHTTP: "503", failureReasons: [.guestHTTP("503")]),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: false
        )

        guard case .recoveryDisabled(let plan) = decision else {
            return XCTFail("expected disabled recovery decision")
        }
        XCTAssertEqual(plan.detectedLogMessage, "watchdog detected unhealthy runtime reasons=guest-http-503")
        XCTAssertEqual(plan.startedStatusMessage, "watchdog recovery started: guest-http-503")
        XCTAssertEqual(plan.finalStatus, .degraded)
        XCTAssertEqual(
            plan.finalStatusMessage,
            "watchdog detected unhealthy runtime; automatic recovery is disabled: guest-http-503"
        )
        XCTAssertEqual(plan.printMessage, "watchdog: recovery disabled")
    }

    func testRecoveryDecisionPlansPlatformVMRestartForRuntimeReadinessFailure() {
        let useCase = WatchdogRuntimeUseCase()

        let decision = useCase.recoveryDecision(
            snapshot: healthSnapshot(
                vmLifecycle: runningLifecycle(),
                hostProxyHTTP: "502",
                guestHTTP: "503",
                failureReasons: [.hostProxyHTTP("502"), .guestHTTP("503")]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        guard case .recover(let plan) = decision else {
            return XCTFail("expected recovery execution plan")
        }
        XCTAssertEqual(plan.reason, "host-proxy-http-502, guest-http-503")
        XCTAssertTrue(plan.recoveryPlan.restartVM)
        XCTAssertTrue(plan.recoveryPlan.restartProxy)
        XCTAssertEqual(plan.vmRestartEventMessage, "watchdog restart dispatched services=vm,guest-log-sync")
        XCTAssertEqual(plan.proxyRestartEventMessage, "watchdog restart dispatched services=proxy")
        XCTAssertEqual(
            plan.plannedEventMessage,
            "watchdog platform recovery planned vm=true proxy=true reasons=guest-http-unhealthy-503,vm-restart-requires-proxy-restart"
        )
    }

    func testRecoveryDecisionPlansExplicitVMRestartEventsForMissingVMIP() {
        let useCase = WatchdogRuntimeUseCase()

        let decision = useCase.recoveryDecision(
            snapshot: healthSnapshot(
                vmLifecycle: runningLifecycle(),
                vmIP: nil,
                guestHTTP: RuntimeHTTPStatusText.missingVMIP,
                failureReasons: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        guard case .recover(let plan) = decision else {
            return XCTFail("expected recovery execution plan")
        }
        XCTAssertTrue(plan.recoveryPlan.restartVM)
        XCTAssertTrue(plan.recoveryPlan.restartProxy)
        XCTAssertEqual(
            plan.vmRestartEventMessage,
            "watchdog restart dispatched services=vm,guest-log-sync"
        )
        XCTAssertEqual(plan.proxyRestartEventMessage, "watchdog restart dispatched services=proxy")
        XCTAssertEqual(
            plan.plannedEventMessage,
            "watchdog platform recovery planned vm=true proxy=true reasons=missing-vm-ip,guest-http-unhealthy-missing-vm-ip,vm-restart-requires-proxy-restart"
        )
    }

    func testRecoveryDecisionDefersWhenServiceStatesAreReadFailures() {
        let useCase = WatchdogRuntimeUseCase()

        let decision = useCase.recoveryDecision(
            snapshot: healthSnapshot(
                vmService: .readFailed("launchctl denied"),
                proxyService: .permissionDenied("launchctl denied"),
                failureReasons: [
                    .vmService("read failed: launchctl denied"),
                    .proxyService("permission denied: launchctl denied"),
                ]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        guard case .recoveryDeferred(let plan) = decision else {
            return XCTFail("expected recovery deferred decision")
        }
        XCTAssertEqual(plan.status, .degraded)
        XCTAssertEqual(
            plan.message,
            "watchdog recovery deferred: recovery-blocked-vm-service-state-read_failed__launchctl_denied, recovery-blocked-proxy-service-state-permission_denied__launchctl_denied"
        )
        XCTAssertEqual(plan.printMessage, "watchdog: deferred")
    }

    func testLifecycleMarkPlanOnlyMarksStartingOrBootstrappingLifecycle() {
        let useCase = WatchdogRuntimeUseCase()
        let bootstrapping = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        )

        XCTAssertEqual(useCase.lifecycleMarkPlan(healthSnapshot(vmLifecycle: nil)).lifecycle, nil)
        XCTAssertEqual(useCase.lifecycleMarkPlan(healthSnapshot(vmLifecycle: runningLifecycle())).lifecycle, nil)
        XCTAssertEqual(useCase.lifecycleMarkPlan(healthSnapshot(vmLifecycle: bootstrapping)).lifecycle, bootstrapping)
        XCTAssertEqual(
            useCase.lifecycleMarkPlan(healthSnapshot(vmLifecycle: bootstrapping)).eventMessage,
            "VM lifecycle marked running after healthy runtime observation"
        )
    }

    func testRecoveryCompletionPlanKeepsFailedRecoveryCriticalWithoutFallback() {
        let useCase = WatchdogRuntimeUseCase()

        let plan = useCase.recoveryCompletionPlan(healthSnapshot(
            guestHTTP: "503",
            failureReasons: [.guestHTTP("503")]
        ))

        XCTAssertEqual(plan.status, .critical)
        XCTAssertEqual(plan.message, "watchdog recovery failed: guest-http-503")
        XCTAssertEqual(plan.printMessage, "watchdog: critical")
    }

}

private func healthSnapshot(
    vmExecutable: RuntimeFileState = .executable,
    proxyExecutable: RuntimeFileState = .executable,
    rootfsBase: RuntimeFileState = .present,
    vmDisk: RuntimeFileState = .present,
    vmService: RuntimeServiceState = .loaded,
    proxyService: RuntimeServiceState = .loaded,
    watchdogService: RuntimeServiceState = .loaded,
    vmLifecycle: RuntimeVMLifecycleDocument? = nil,
    vmState: RuntimeVMState = .running,
    vmErrors: [RuntimeVMError] = [],
    vmIP: String? = "192.168.64.2",
    proxyPort: Int = 80,
    hostProxyHTTP: String = "200",
    guestHTTP: String = "200",
    redisUIHTTP: String = "200",
    swaggerUIHTTP: String = "200",
    failureReasons: [RuntimeFailureReason] = []
) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: vmExecutable,
        proxyExecutable: proxyExecutable,
        rootfsBase: rootfsBase,
        vmDisk: vmDisk,
        vmService: vmService,
        proxyService: proxyService,
        watchdogService: watchdogService,
        vmLifecycle: vmLifecycle,
        vmState: vmState,
        vmErrors: vmErrors,
        vmIP: vmIP,
        proxyPort: proxyPort,
        hostProxyHTTP: hostProxyHTTP,
        guestHTTP: guestHTTP,
        redisUIHTTP: redisUIHTTP,
        swaggerUIHTTP: swaggerUIHTTP,
        failureReasons: failureReasons
    )
}

private func runningLifecycle() -> RuntimeVMLifecycleDocument {
    RuntimeVMLifecycleDocument(
        state: .running,
        startedAt: "2026-05-31T00:00:00Z",
        updatedAt: "2026-05-31T00:00:01Z"
    )
}
