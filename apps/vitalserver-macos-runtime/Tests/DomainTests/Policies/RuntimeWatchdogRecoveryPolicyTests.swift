import Contracts
import Application
@testable import Domain
import XCTest
import Errors

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

    func testSuppressesAutomaticRecoveryForPreservationSensitiveFailureReasons() {
        let snapshot = healthSnapshot(
            guestHTTP: "failed",
            failureReasons: [.unknown("vm-disk-attachment-invalid")]
        )

        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: snapshot,
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(decision, .recoverySuppressed(reason: "vm-disk-attachment-invalid"))
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

    func testMissingFailureReasonsBlockAutomaticRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                vmState: .unreachable,
                guestHTTP: "503",
                failureReasons: []
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .unrecoverable(reason: RuntimeHealthSnapshotPolicy.missingFailureReasons)
        )
    }

    func testBootstrapObservationIssueBlocksAutomaticRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                vmLifecycle: runningLifecycle(),
                guestHTTP: "503",
                failureReasons: [.guestHTTP("503"), .guestBootstrapResultMissing]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .unrecoverable(reason: "guest-bootstrap-result-missing")
        )
    }

    func testObservationSourceIssueBlocksAutomaticRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                failureReasons: [.vitalDBObservationMissing]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .unrecoverable(reason: "vitaldb-observation-missing")
        )
    }

    func testReportsUnrecoverableWhenInstalledArtifactsAreMissing() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(vmExecutable: .missing, failureReasons: [.missingVMBin]),
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(decision, .unrecoverable(reason: "missing-vm-bin"))
    }

    func testCreatesRecoveryPlanForRecoverableRuntimeFailure() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                vmLifecycle: runningLifecycle(),
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
                plan: RuntimeRecoveryPlan(
                    canRecover: true,
                    restartVM: true,
                    restartGuestLogSync: true,
                    restartProxy: true,
                    restartReasons: [
                        .guestHTTPUnhealthy("503"),
                        .vmRestartRequiresProxyRestart,
                    ]
                )
            )
        )
    }

    func testExpiredBootstrappingKernelPanicCanRecoverWithVMRestartDespiteHostProxyProbeReadFailure() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                vmLifecycle: RuntimeVMLifecycleDocument(
                    state: .bootstrapping,
                    startedAt: "2026-06-07T09:30:11Z",
                    updatedAt: "2026-06-07T09:30:11Z",
                    deadlineAt: "2000-01-01T00:00:00Z"
                ),
                vmIP: nil,
                hostProxyHTTP: "failed",
                guestHTTP: RuntimeHTTPStatusText.missingVMIP,
                failureReasons: [
                    .guestRuntimeStateStale,
                    .vmLifecycleDocumentStale,
                    .hostProxyHTTP("failed"),
                    .unknown("audit-proxy-http-failed"),
                ]
            ),
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .recover(
                reason: "guest-runtime-state-stale, vm-lifecycle-document-stale, host-proxy-http-failed, audit-proxy-http-failed",
                plan: RuntimeRecoveryPlan(
                    canRecover: true,
                    restartVM: true,
                    restartGuestLogSync: true,
                    restartProxy: true,
                    restartReasons: [
                        .missingVMIP,
                        .guestHTTPUnhealthy(RuntimeHTTPStatusText.missingVMIP),
                        .vmRestartRequiresProxyRestart,
                        .hostProxyLivenessUnhealthy("failed"),
                    ]
                )
            )
        )
    }

    func testStaleGuestRuntimeStateContainerObservationCanRecoverWithVMAndProxyRestart() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                vmLifecycle: runningLifecycle(),
                vmIP: nil,
                hostProxyHTTP: "http-probe-command-failed exitCode=7",
                guestHTTP: RuntimeHTTPStatusText.missingVMIP,
                containerObservation: RuntimeContainerObservation(
                    auditProxyHTTP: "failed",
                    auditProxyStatus: nil,
                    auditProxyStatusReadError: "failed",
                    containerLogsPresent: true,
                    containerLogsBytes: 128,
                    composeServicesReadState: .stale,
                    composeServicesReadError: "guest-runtime-state-stale"
                ),
                failureReasons: [
                    .guestRuntimeStateStale,
                    .hostProxyHTTP("http-probe-command-failed exitCode=7"),
                    .auditProxyHTTP("failed"),
                    .containerObservationReadFailed("guest-runtime-state-stale"),
                ]
            ),
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .recover(
                reason: "guest-runtime-state-stale, host-proxy-http-http-probe-command-failed exitCode=7, audit-proxy-http-failed, container-observation-read-failed-guest-runtime-state-stale",
                plan: RuntimeRecoveryPlan(
                    canRecover: true,
                    restartVM: true,
                    restartGuestLogSync: true,
                    restartProxy: true,
                    restartReasons: [
                        .missingVMIP,
                        .guestHTTPUnhealthy(RuntimeHTTPStatusText.missingVMIP),
                        .containerFailureRequiresVMRestart,
                        .vmRestartRequiresProxyRestart,
                        .hostProxyLivenessUnhealthy("failed"),
                    ]
                )
            )
        )
    }

    func testMissingVMLifecycleBlocksAutomaticVMRestart() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                guestHTTP: "503",
                failureReasons: [.guestHTTP("503")]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .unrecoverable(reason: "recovery-blocked-missing-vm-lifecycle-for-vm-restart")
        )
    }

    func testServiceStateReadFailureDefersAutomaticRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
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

        XCTAssertEqual(
            decision,
            .recoveryDeferred(
                reason: "recovery-blocked-vm-service-state-read_failed__launchctl_denied, recovery-blocked-proxy-service-state-permission_denied__launchctl_denied"
            )
        )
    }

    func testGuestHTTPReadFailureBlocksAutomaticRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                guestHTTP: "failed",
                failureReasons: [.guestHTTP("failed")]
            ),
            hostProxyLivenessHTTP: "204",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .unrecoverable(reason: "recovery-blocked-guest-http-read-failed-failed")
        )
    }

    func testHostProxyHTTPReadFailureBlocksAutomaticRecovery() {
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: healthSnapshot(
                hostProxyHTTP: RuntimeHTTPStatusText.invalidResponse,
                failureReasons: [.hostProxyHTTP(RuntimeHTTPStatusText.invalidResponse)]
            ),
            hostProxyLivenessHTTP: "failed",
            automaticRecoveryEnabled: true
        )

        XCTAssertEqual(
            decision,
            .unrecoverable(
                reason: "recovery-blocked-host-proxy-readiness-http-read-failed-invalid-response, recovery-blocked-host-proxy-liveness-http-read-failed-failed"
            )
        )
    }
}

private func runningLifecycle() -> RuntimeVMLifecycleDocument {
    RuntimeVMLifecycleDocument(
        state: .running,
        startedAt: "2026-05-31T00:00:00Z",
        updatedAt: "2026-05-31T00:00:01Z"
    )
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
    containerObservation: RuntimeContainerObservation? = nil,
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
        containerObservation: containerObservation,
        failureReasons: failureReasons
    )
}
