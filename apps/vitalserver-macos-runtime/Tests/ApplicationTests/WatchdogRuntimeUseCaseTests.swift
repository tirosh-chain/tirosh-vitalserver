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
            failureReasons: [.guestHTTP("failed")]
        ))

        guard case .recoverySuppressed(let plan) = decision else {
            return XCTFail("expected suppressed recovery decision")
        }
        XCTAssertEqual(plan.status, .critical)
        XCTAssertEqual(plan.message, "watchdog recovery suppressed: vm-guest-filesystem-read-only")
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

    func testRecoveryDecisionPlansExplicitRestartEvents() {
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
        XCTAssertEqual(
            plan.vmRestartEventMessage,
            "watchdog restart dispatched services=vm,guest-log-sync"
        )
        XCTAssertEqual(plan.proxyRestartEventMessage, "watchdog restart dispatched services=proxy")
        XCTAssertEqual(
            plan.plannedEventMessage,
            "watchdog recovery planned vm=true proxy=true reasons=guest-http-unhealthy-503,vm-restart-requires-proxy-restart"
        )
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

    func testStatusManagedOperationGuardPlanBlocksFreshProtectedOperation() {
        let useCase = WatchdogRuntimeUseCase()

        let plan = useCase.statusManagedOperationGuardPlan(
            status: status(level: .updating, operation: .applyBundle, updatedAt: "2026-05-22T00:00:00Z"),
            now: date("2026-05-22T00:05:00Z"),
            graceSeconds: 1_800
        )

        XCTAssertEqual(plan.activeOperation, .applyBundle)
        XCTAssertNil(plan.logMessage)
    }

    func testStatusManagedOperationGuardPlanDoesNotHideInvalidOrStaleState() {
        let useCase = WatchdogRuntimeUseCase()

        let invalid = useCase.statusManagedOperationGuardPlan(
            status: status(level: .recovering, operation: .rollback, updatedAt: "not-a-date"),
            now: date("2026-05-22T00:05:00Z"),
            graceSeconds: 1_800
        )
        let stale = useCase.statusManagedOperationGuardPlan(
            status: status(level: .recovering, operation: .rollback, updatedAt: "2026-05-22T00:00:00Z"),
            now: date("2026-05-22T00:31:00Z"),
            graceSeconds: 1_800
        )

        XCTAssertNil(invalid.activeOperation)
        XCTAssertEqual(
            invalid.logMessage,
            "watchdog active operation guard ignored invalid updatedAt operation=rollback updatedAt=not-a-date"
        )
        XCTAssertNil(stale.activeOperation)
        XCTAssertEqual(
            stale.logMessage,
            "watchdog active operation guard expired operation=rollback ageSeconds=1860"
        )
    }

    func testGuestBootstrapGuardKeepsMissingUpdatedAtExplicitlyActive() {
        let useCase = WatchdogRuntimeUseCase()

        let plan = useCase.guestBootstrapManagedOperationGuardPlan(
            operation: .unknown("bootstrap"),
            updatedAt: nil,
            now: date("2026-05-22T00:31:00Z"),
            graceSeconds: 1_800
        )

        XCTAssertEqual(plan.activeOperation, .unknown("bootstrap"))
        XCTAssertEqual(
            plan.logMessage,
            "watchdog guest bootstrap guard active without updatedAt operation=bootstrap"
        )
    }
}

private func healthSnapshot(
    vmExecutable: Bool = true,
    proxyExecutable: Bool = true,
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

private func status(
    level: RuntimeStatusLevel,
    operation: RuntimeOperation,
    updatedAt: String
) -> RuntimeStatusDocument {
    RuntimeStatusDocument(
        product: "VitalServerHelper",
        status: level,
        operation: operation,
        message: "status",
        updatedAt: updatedAt,
        productRoot: "/product",
        runtimeHome: "/product/vm",
        runtimeVersion: "0.1.0",
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmIP: "192.168.64.2",
        proxyPort: 80,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        rootfsBase: .present,
        vmDisk: .present,
        failureReasons: [],
        latestBackup: nil
    )
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
