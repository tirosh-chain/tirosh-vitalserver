import Contracts
@testable import Core
import XCTest

final class RuntimeWatchdogRecoveryPolicyTests: XCTestCase {
    func testHealthySnapshotDoesNotNeedRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(decision, .healthy)
    }

    func testSuppressesAutomaticRecoveryForGuestStorageErrors() {
        let snapshot = healthSnapshot(
            vmErrors: [.guestFilesystemReadOnly],
            failureReasons: [.guestHTTP("failed")]
        )

        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: snapshot,
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(decision, .recoverySuppressed(reason: "vm-guest-filesystem-read-only"))
    }

    func testDefersAutomaticRecoveryForBootstrappingVMLifecycle() {
        let snapshot = healthSnapshot(
            vmLifecycle: RuntimeVMLifecycleDocument(
                state: .bootstrapping,
                startedAt: "2026-05-31T00:00:00Z",
                updatedAt: "2026-05-31T00:00:01Z",
                deadlineAt: "2999-01-01T00:00:00Z"
            ),
            vmIP: nil,
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            failureReasons: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)]
        )

        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: snapshot,
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(decision, .recoveryDeferred(reason: "vm-lifecycle-bootstrapping"))
    }

    func testReportsRecoveryDisabledWithoutCreatingPlan() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(guestHTTP: "failed", failureReasons: [.guestHTTP("failed")]),
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: false
        )

        XCTAssertEqual(decision, .recoveryDisabled(reason: "guest-http-failed"))
    }

    func testReportsUnrecoverableWhenInstalledArtifactsAreMissing() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(vmExecutable: false, failureReasons: [.missingVMBin]),
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(decision, .unrecoverable(reason: "missing-vm-bin"))
    }

    func testCreatesRecoveryPlanForRecoverableRuntimeFailure() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                hostProxyHTTP: "502",
                guestHTTP: "503",
                failureReasons: [.hostProxyHTTP("502"), .guestHTTP("503")]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .recover(
                reason: "host-proxy-http-502, guest-http-503",
                plan: RuntimeRecoveryPlan(canRecover: true, restartVM: true, restartProxy: true)
            )
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
