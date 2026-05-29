import Core
import Contracts
import XCTest

final class RuntimeHealthEvaluatorTests: XCTestCase {
    func testHealthyInputHasNoFailureReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput())

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.vmState, .running)
        XCTAssertEqual(snapshot.vmErrors, [])
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testMissingArtifactsAndServicesProduceTypedReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vmExecutable: false,
            proxyExecutable: false,
            rootfsBase: .missing,
            vmDisk: .missing,
            vmService: .notLoaded,
            proxyService: .notLoaded,
            watchdogService: .notLoaded
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .missingVMBin,
            .missingRootfsBase,
            .missingVMDisk,
            .vmService("not loaded"),
            .missingProxyRunner,
            .proxyService("not loaded"),
            .watchdogService("not loaded"),
        ])
        XCTAssertEqual(snapshot.vmErrors, [
            .missingExecutable,
            .missingRootfsBase,
            .missingDisk,
            .serviceNotLoaded("not loaded"),
        ])
    }

    func testReadinessFailuresIncludeProxyPortAndBootstrapReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            hostProxyHTTP: "502",
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            redisUIHTTP: "failed",
            swaggerUIHTTP: "404",
            proxyPortFailureReasons: [.proxyPortInUse(port: 80, listeners: "nginx-1234")],
            guestBootstrapFailureReason: .guestBootstrapMissingRuntimePackages
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .guestHTTP(RuntimeHTTPStatusText.bootstrapPending),
            .guestBootstrapMissingRuntimePackages,
            .hostProxyHTTP("502"),
            .proxyPortInUse(port: 80, listeners: "nginx-1234"),
        ])
        XCTAssertEqual(snapshot.vmErrors, [
            .guestHTTP(RuntimeHTTPStatusText.bootstrapPending),
            .guestBootstrapMissingRuntimePackages,
        ])
    }

    func testAuxiliaryUIFailuresDoNotTriggerRuntimeRecovery() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            redisUIHTTP: "failed",
            swaggerUIHTTP: "500"
        ))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.redisUIHTTP, "failed")
        XCTAssertEqual(snapshot.swaggerUIHTTP, "500")
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testAuditProxyStatusFailureProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "failed",
                auditProxyStatus: nil,
                containerLogsPresent: true,
                containerLogsBytes: 1024
            )
        ))

        XCTAssertEqual(snapshot.failureReasons, [.auditProxyHTTP("failed")])
    }

    func testAuditProxyCountersAreObservedWithoutTriggeringRecovery() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(auditWriteFailures: 2),
            containerLogsPresent: true,
            containerLogsBytes: 2048
        )
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.containerObservation, observation)
    }

    func testCriticalContainerServiceFailureProducesTypedReason() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 2048,
            composeServices: [
                RuntimeContainerServiceObservation(
                    service: "app",
                    state: "running",
                    health: "unhealthy"
                ),
                RuntimeContainerServiceObservation(
                    service: "redis-ui",
                    state: "exited",
                    health: "unhealthy"
                ),
            ]
        )
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertEqual(snapshot.failureReasons, [
            .containerService(service: "app", state: "unhealthy"),
        ])
    }

    func testCriticalContainerServiceStartingHealthIsNotARecoveryReason() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 2048,
            composeServices: [
                RuntimeContainerServiceObservation(
                    service: "edge",
                    state: "running",
                    health: "starting"
                ),
                RuntimeContainerServiceObservation(
                    service: "vitaldb-observer",
                    state: "running",
                    health: "starting"
                ),
            ]
        )

        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testCriticalVitalDBAnomalyProducesTypedReason() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "a1",
                    kind: .backendUnavailable,
                    severity: .critical,
                    observedAt: "2026-05-25T00:00:00Z",
                    subject: "/socket.io/?EIO=3&transport=websocket",
                    message: "backend-unavailable"
                ),
                VitalDBAnomalyObservation(
                    id: "a2",
                    kind: .duplicateIP,
                    severity: .critical,
                    observedAt: "2026-05-25T00:00:00Z",
                    subject: "10.0.0.10",
                    message: "duplicate-ip"
                ),
                VitalDBAnomalyObservation(
                    id: "a3",
                    kind: .staleRecorder,
                    severity: .warning,
                    observedAt: "2026-05-25T00:00:00Z",
                    subject: "VR_A",
                    message: "stale-recorder"
                ),
            ]
        )

        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(vitalDBObservation: observation))

        XCTAssertEqual(snapshot.failureReasons, [
            .vitalDBAnomaly(kind: "backend-unavailable", subject: "_socket.io__EIO_3_transport_websocket"),
        ])
    }

    func testBootstrapReasonIsIgnoredWhenGuestHTTPIsHealthy() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "200",
            guestBootstrapFailureReason: .guestBootstrapFailed
        ))

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testStaleGuestRuntimeStateProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestRuntimeStateFresh: false
        ))

        XCTAssertFalse(snapshot.isHealthy)
        XCTAssertEqual(snapshot.failureReasons, [.guestRuntimeStateStale])
        XCTAssertEqual(snapshot.vmState, .stale)
        XCTAssertEqual(snapshot.vmErrors, [.runtimeStateStale])
    }

    func testMissingGuestRuntimeStateIsObservableSeparatelyFromGuestHTTP() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "failed",
            guestRuntimeStatePresent: false
        ))

        XCTAssertEqual(snapshot.vmState, .unreachable)
        XCTAssertEqual(snapshot.vmErrors, [.runtimeStateMissing, .guestHTTP("failed")])
        XCTAssertEqual(snapshot.failureReasons.map(\.rawValue), [
            "vm-runtime-state-missing",
            "guest-http-failed",
        ])
    }

    func testVMHealthPolicyDefinesHostAndGuestFailureModes() {
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmIP: nil, guestHTTP: RuntimeHTTPStatusText.missingVMIP)).vmState, .starting)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(guestHTTP: RuntimeHTTPStatusText.bootstrapPending)).vmState, .starting)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmExecutable: false)).vmState, .notInstalled)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmDisk: .missing)).vmState, .failed)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmService: .notLoaded)).vmState, .stopped)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(guestHTTP: "failed")).vmState, .unreachable)
    }

    func testRuntimeHealthEvaluatorUsesExplicitVMHealthPolicy() {
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmExecutable: false)).vmState, .notInstalled)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmDisk: .missing)).vmState, .failed)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmService: .notLoaded)).vmState, .stopped)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmIP: nil, guestHTTP: RuntimeHTTPStatusText.missingVMIP)).vmState, .starting)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(guestHTTP: RuntimeHTTPStatusText.bootstrapPending)).vmState, .starting)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(guestHTTP: "failed")).vmState, .unreachable)
    }

    func testReportedVMErrorsMarkVMFailedAndRemainObservable() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            reportedVMErrors: [.launchFailed("virtualization"), .diskAttachmentInvalid, .guestFilesystemReadOnly, .guestDiskIO]
        ))

        XCTAssertEqual(snapshot.vmState, .failed)
        XCTAssertEqual(snapshot.vmErrors, [
            .launchFailed("virtualization"),
            .diskAttachmentInvalid,
            .guestFilesystemReadOnly,
            .guestDiskIO,
        ])
        XCTAssertEqual(snapshot.failureReasons.map(\.rawValue), [
            "vm-launch-failed-virtualization",
            "vm-disk-attachment-invalid",
            "vm-guest-filesystem-read-only",
            "vm-guest-disk-io-error",
        ])
    }

    private func healthyInput(
        vmExecutable: Bool = true,
        proxyExecutable: Bool = true,
        rootfsBase: RuntimeFileState = .present,
        vmDisk: RuntimeFileState = .present,
        vmService: RuntimeServiceState = .loaded,
        proxyService: RuntimeServiceState = .loaded,
        watchdogService: RuntimeServiceState = .loaded,
        vmIP: String? = "192.168.64.2",
        proxyPort: Int = 80,
        hostProxyHTTP: String = "200",
        guestHTTP: String = "200",
        guestRuntimeStatePresent: Bool = true,
        guestRuntimeStateFresh: Bool = true,
        redisUIHTTP: String = "200",
        swaggerUIHTTP: String = "200",
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
        reportedVMErrors: [RuntimeVMError] = [],
        proxyPortFailureReasons: [RuntimeFailureReason] = [],
        guestBootstrapFailureReason: RuntimeFailureReason? = nil
    ) -> RuntimeHealthInput {
        RuntimeHealthInput(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            vmService: vmService,
            proxyService: proxyService,
            watchdogService: watchdogService,
            vmIP: vmIP,
            proxyPort: proxyPort,
            hostProxyHTTP: hostProxyHTTP,
            guestHTTP: guestHTTP,
            guestRuntimeStatePresent: guestRuntimeStatePresent,
            guestRuntimeStateFresh: guestRuntimeStateFresh,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            containerObservation: containerObservation,
            vitalDBObservation: vitalDBObservation,
            reportedVMErrors: reportedVMErrors,
            proxyPortFailureReasons: proxyPortFailureReasons,
            guestBootstrapFailureReason: guestBootstrapFailureReason
        )
    }
}
