import Contracts
import Application
@testable import Domain
import XCTest
import Errors

final class RuntimeHealthEvaluatorTests: XCTestCase {
    func testHealthyInputHasNoFailureReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput())

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.vmState, .running)
        XCTAssertEqual(snapshot.vmErrors, [])
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testGuestReadinessNotReportedDoesNotCreateCurrentHealthFailure() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestReadiness: .notReported
        ))

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.vmErrors, [])
        XCTAssertEqual(snapshot.failureReasons, [])
        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
    }

    func testMissingArtifactsAndServicesProduceTypedReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vmExecutable: .missing,
            proxyExecutable: .missing,
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

    func testReadinessFailuresIncludeProxyPortReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            hostProxyHTTP: "502",
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            redisUIHTTP: "failed",
            swaggerUIHTTP: "404",
            proxyPortFailureReasons: [.proxyPortInUse(port: 80, listeners: "nginx-1234")]
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .guestHTTP(RuntimeHTTPStatusText.bootstrapPending),
            .hostProxyHTTP("502"),
            .proxyPortInUse(port: 80, listeners: "nginx-1234"),
        ])
        XCTAssertEqual(snapshot.vmErrors, [
            .guestHTTP(RuntimeHTTPStatusText.bootstrapPending),
        ])
    }

    func testAuxiliaryUIFailuresDoNotTriggerRuntimeRecovery() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            redisUIHTTP: "failed",
            swaggerUIHTTP: "500"
        ))

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.redisUIHTTP, "failed")
        XCTAssertEqual(snapshot.swaggerUIHTTP, "500")
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testHealthyGuestServiceStatusesKeepSnapshotHealthy() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .loaded([
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ])
        ))

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testStackStatusProbeErrorsDoNotBecomeRuntimeHealthFailuresWhenServicesAreHealthy() {
        let stackStatus = RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-01T00:00:00Z",
            services: [
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ],
            probeErrors: [
                GuestRuntimeProbeError(
                    source: "docker stats",
                    message: "timed out after 1 seconds"
                ),
            ]
        )

        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .loaded(stackStatus.services)
        ))

        XCTAssertEqual(stackStatus.probeErrors, [
            GuestRuntimeProbeError(
                source: "docker stats",
                message: "timed out after 1 seconds"
            ),
        ])
        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testGuestServiceStatusesAreTheRecorderIngressHealthAuthority() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .loaded([
                RuntimeGuestControlServiceStatus(
                    service: "recorder-ingress",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ])
        ))

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testGuestServiceReadFailureProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .readFailed("guest control api unavailable")
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .guestServiceObservationReadFailed("guest_control_api_unavailable"),
        ])
    }

    func testGuestServiceStatusFailureProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .loaded([
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "unhealthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ])
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .guestService(service: "app", state: "unhealthy"),
        ])
    }

    func testGuestServiceDesiredStoppedSuppressesStoppedStatusFailure() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .loaded([
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "stopped",
                    health: "unknown",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "redis",
                    state: "stopped",
                    health: "unknown",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ]),
            guestServiceResources: [
                guestServiceResource(service: "app", desiredState: "stopped"),
                guestServiceResource(service: "redis", desiredState: "running"),
            ]
        ))

        XCTAssertFalse(snapshot.failureReasons.contains(.guestService(service: "app", state: "stopped")))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestService(service: "redis", state: "stopped")))
    }

    func testGuestServiceResourceReadIssueProducesTypedFailureReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestServiceStatuses: .loaded([
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ]),
            guestServiceResourceReadIssues: [
                RuntimeGuestServiceResourceReadIssue(
                    service: "app",
                    message: "resource controller unavailable"
                ),
            ]
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .guestServiceObservationReadFailed("app_resource_controller_unavailable"),
        ])
    }

    func testCriticalVitalDBAnomalyIsPreservedWithoutRuntimeFailureReason() {
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

        XCTAssertEqual(snapshot.failureReasons, [])
        XCTAssertEqual(snapshot.vitalDBObservation, observation)
    }

    func testMissingVitalDBObservationDoesNotProduceRuntimeFailureReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vitalDBObservationInput: .missing
        ))

        XCTAssertEqual(snapshot.failureReasons, [])
        XCTAssertNil(snapshot.vitalDBObservation)
    }

    func testVitalDBObservationReadFailureDoesNotProduceRuntimeFailureReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vitalDBObservationInput: .readFailed("decode failed")
        ))

        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testRecorderAnomaliesRemainOperatorVisibleWithoutRuntimeRestartReason() {
        let duplicateIP = VitalDBAnomalyObservation(
            id: "a1",
            kind: .duplicateIP,
            severity: .critical,
            observedAt: "2026-05-25T00:00:00Z",
            subject: "10.0.0.10",
            message: "duplicate-ip"
        )
        let staleRecorder = VitalDBAnomalyObservation(
            id: "a2",
            kind: .staleRecorder,
            severity: .warning,
            observedAt: "2026-05-25T00:00:00Z",
            subject: "VR_A",
            message: "stale-recorder"
        )
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            anomalies: [duplicateIP, staleRecorder]
        )

        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(vitalDBObservation: observation))

        XCTAssertTrue(RuntimeObservationHealthPolicy.isOperatorVisibleOnlyAnomaly(duplicateIP))
        XCTAssertTrue(RuntimeObservationHealthPolicy.isOperatorVisibleOnlyAnomaly(staleRecorder))
        XCTAssertFalse(RuntimeObservationHealthPolicy.isRuntimeHealthAnomaly(duplicateIP))
        XCTAssertEqual(snapshot.failureReasons, [])
        XCTAssertEqual(snapshot.vitalDBObservation?.anomalies, [duplicateIP, staleRecorder])
    }

    func testBootstrappingLifecycleUsesGuestHTTPWithoutBootstrapResultFileInput() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vmLifecycle: RuntimeVMLifecycleDocument(
                state: .bootstrapping,
                startedAt: "2026-05-31T00:00:00Z",
                updatedAt: "2026-05-31T00:00:01Z",
                deadlineAt: "2026-05-31T00:10:00Z"
            ),
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending
        ))

        XCTAssertEqual(snapshot.vmErrors, [.guestHTTP(RuntimeHTTPStatusText.bootstrapPending)])
        XCTAssertEqual(snapshot.failureReasons, [.guestHTTP(RuntimeHTTPStatusText.bootstrapPending)])
        XCTAssertEqual(snapshot.vmState, .starting)
    }

    func testVMHealthPolicyDefinesHostAndGuestFailureModes() {
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmIP: nil)).vmState, .starting)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(guestHTTP: RuntimeHTTPStatusText.bootstrapPending)).vmState, .starting)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmExecutable: .missing)).vmState, .notInstalled)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmDisk: .missing)).vmState, .failed)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(vmService: .notLoaded)).vmState, .stopped)
        XCTAssertEqual(RuntimeVMHealthPolicy.evaluate(healthyInput(guestHTTP: "failed")).vmState, .unreachable)
    }

    func testRuntimeHealthEvaluatorUsesExplicitVMHealthPolicy() {
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmExecutable: .missing)).vmState, .notInstalled)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmDisk: .missing)).vmState, .failed)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmService: .notLoaded)).vmState, .stopped)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(vmIP: nil)).vmState, .starting)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(guestHTTP: RuntimeHTTPStatusText.bootstrapPending)).vmState, .starting)
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(healthyInput(guestHTTP: "failed")).vmState, .unreachable)
    }

    func testVMLifecycleTerminalReasonReportsStoragePreservingVMError() {
        let cases: [(RuntimeVMLifecycleTerminalReason, RuntimeVMError, RuntimeFailureReason)] = [
            (.launchFailed, .launchFailed("launch-failed"), .vmLaunchFailed("launch-failed")),
            (.diskAttachmentInvalid, .diskAttachmentInvalid, .vmDiskAttachmentInvalid),
            (.guestFilesystemReadOnly, .guestFilesystemReadOnly, .guestFilesystemReadOnly),
            (.guestDiskIO, .guestDiskIO, .guestDiskIO),
        ]

        for (terminalReason, expectedVMError, expectedFailureReason) in cases {
            let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
                vmLifecycle: RuntimeVMLifecycleDocument(
                    state: .failed,
                    startedAt: "2026-05-31T00:00:00Z",
                    updatedAt: "2026-05-31T00:00:05Z",
                    terminalReason: terminalReason
                )
            ))

            XCTAssertEqual(snapshot.vmState, .failed)
            XCTAssertEqual(snapshot.vmErrors, [expectedVMError])
            XCTAssertEqual(snapshot.failureReasons, [expectedFailureReason])
        }
    }

    private func healthyInput(
        vmExecutable: RuntimeFileState = .executable,
        proxyExecutable: RuntimeFileState = .executable,
        rootfsBase: RuntimeFileState = .present,
        vmDisk: RuntimeFileState = .present,
        vmService: RuntimeServiceState = .loaded,
        proxyService: RuntimeServiceState = .loaded,
        watchdogService: RuntimeServiceState = .loaded,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        guestReadiness: RuntimeGuestReadinessInput? = nil,
        vmIP: String? = "192.168.64.2",
        proxyPort: Int = 80,
        hostProxyHTTP: String = "200",
        guestHTTP: String = "200",
        redisUIHTTP: String = "200",
        swaggerUIHTTP: String = "200",
        vitalDBObservation: VitalDBObservationDocument? = nil,
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
        guestServiceResources: [RuntimeGuestServiceResource] = [],
        guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = [],
        vitalDBObservationInput: RuntimeObservationInput<VitalDBObservationDocument>? = nil,
        proxyPortFailureReasons: [RuntimeFailureReason] = []
    ) -> RuntimeHealthInput {
        RuntimeHealthInput(
            vmExecutable: vmExecutable,
            proxyExecutable: proxyExecutable,
            rootfsBase: rootfsBase,
            vmDisk: vmDisk,
            vmService: vmService,
            proxyService: proxyService,
            watchdogService: watchdogService,
            vmLifecycle: vmLifecycle,
            guestReadiness: guestReadiness ?? .reported(
                vmIP: vmIP,
                guestHTTP: guestHTTPInput(guestHTTP)
            ),
            proxyPort: proxyPort,
            proxyPortReadState: .loaded(proxyPort),
            hostProxyHTTP: hostProxyHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            guestServiceStatuses: guestServiceStatuses,
            guestServiceResources: guestServiceResources,
            guestServiceResourceReadIssues: guestServiceResourceReadIssues,
            vitalDBObservation: vitalDBObservationInput
                ?? vitalDBObservation.map(RuntimeObservationInput.loaded)
                ?? .notReported,
            proxyPortFailureReasons: proxyPortFailureReasons
        )
    }

    private func guestServiceResource(
        service: String,
        desiredState: String
    ) -> RuntimeGuestServiceResource {
        RuntimeGuestServiceResource(
            service: service,
            spec: RuntimeGuestServiceSpec(state: desiredState, desiredState: desiredState),
            status: RuntimeGuestServiceStatusRead(state: desiredState),
            conditions: []
        )
    }

    private func guestHTTPInput(_ value: String) -> RuntimeGuestHTTPStatusInput {
        if Int(value) != nil
            || value == RuntimeHTTPStatusText.bootstrapPending
            || value == RuntimeHTTPStatusText.missingVMIP {
            return .reportedStatus(value)
        }
        return .probeFailed(value)
    }
}
