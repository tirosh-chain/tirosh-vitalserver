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

    func testReadinessFailuresIncludeProxyPortAndBootstrapReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            hostProxyHTTP: "502",
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            redisUIHTTP: "failed",
            swaggerUIHTTP: "404",
            proxyPortFailureReasons: [.proxyPortInUse(port: 80, listeners: "nginx-1234")],
            guestBootstrapAssessment: .failed(.guestBootstrapMissingRuntimePackages)
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

    func testExplicitBootstrapFailureIsReportedWhenGuestRuntimeStateIsMissing() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestRuntimeState: .missing,
            guestBootstrapAssessment: .failed(.guestBootstrapMissingRuntimePackages)
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .guestRuntimeStateMissing,
            .guestBootstrapMissingRuntimePackages,
        ])
        XCTAssertEqual(snapshot.vmErrors, [
            .runtimeStateMissing,
            .guestBootstrapMissingRuntimePackages,
        ])
        XCTAssertEqual(snapshot.vmState, .failed)
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

    func testRecorderIngressStatusFailureProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            containerObservation: RuntimeContainerObservation(
                recorderIngressHTTP: "failed",
                recorderIngressStatus: nil,
                containerLogsPresent: true,
                containerLogsBytes: 1024
            )
        ))

        XCTAssertEqual(snapshot.failureReasons, [.recorderIngressHTTP("failed")])
    }

    func testRecorderIngressCountersAreObservedWithoutTriggeringRecovery() {
        let observation = RuntimeContainerObservation(
            recorderIngressHTTP: "200",
            recorderIngressStatus: RuntimeRecorderIngressStatusDocument(auditWriteFailures: 2),
            containerLogsPresent: true,
            containerLogsBytes: 2048
        )
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.containerObservation, observation)
    }

    func testCriticalContainerServiceFailureProducesTypedReason() {
        let observation = RuntimeContainerObservation(
            recorderIngressHTTP: "200",
            recorderIngressStatus: nil,
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

    func testMissingComposeServicesProducesContainerObservationMissingReason() {
        let observation = RuntimeContainerObservation(
            recorderIngressHTTP: "200",
            recorderIngressStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 2048,
            composeServicesReadState: .missing,
            composeServices: [],
            composeServicesReadError: "container-services-missing"
        )

        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertEqual(snapshot.failureReasons, [.containerObservationMissing])
    }

    func testInvalidComposeServicesProducesContainerObservationReadFailedReason() {
        let observation = RuntimeContainerObservation(
            recorderIngressHTTP: "200",
            recorderIngressStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 2048,
            composeServicesReadState: .invalid,
            composeServices: [],
            composeServicesReadError: "guest-runtime-state-invalid"
        )

        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(containerObservation: observation))

        XCTAssertEqual(snapshot.failureReasons, [.containerObservationReadFailed("guest-runtime-state-invalid")])
    }

    func testCriticalContainerServiceStartingHealthIsNotARecoveryReason() {
        let observation = RuntimeContainerObservation(
            recorderIngressHTTP: "200",
            recorderIngressStatus: nil,
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

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
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

    func testMissingObservationSourcesProduceTypedReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            containerObservationInput: .missing,
            vitalDBObservationInput: .missing
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .containerObservationMissing,
            .vitalDBObservationMissing,
        ])
        XCTAssertNil(snapshot.containerObservation)
        XCTAssertNil(snapshot.vitalDBObservation)
    }

    func testObservationReadFailuresProduceTypedReasons() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            containerObservationInput: .readFailed("permission denied"),
            vitalDBObservationInput: .readFailed("decode failed")
        ))

        XCTAssertEqual(snapshot.failureReasons, [
            .containerObservationReadFailed("permission_denied"),
            .vitalDBObservationReadFailed("decode_failed"),
        ])
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

    func testExplicitBootstrapFailureIsReportedEvenWhenGuestHTTPIsHealthy() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "200",
            guestBootstrapAssessment: .failed(.guestBootstrapFailed)
        ))

        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.vmErrors, [.guestBootstrapFailed])
        XCTAssertEqual(snapshot.failureReasons, [.guestBootstrapFailed])
    }

    func testNotCurrentBootBootstrapResultIsIgnoredWhenGuestHTTPIsHealthy() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "200",
            guestBootstrapAssessment: .notCurrentBoot
        ))

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.failureReasons, [])
    }

    func testMissingBootstrapResultIsObservableWhenGuestHTTPFailsOutsideBootstrapLifecycle() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "failed",
            guestBootstrapAssessment: .missing
        ))

        XCTAssertEqual(snapshot.vmErrors, [
            .guestHTTPProbeFailed("failed"),
            .guestBootstrapResultMissing,
        ])
        XCTAssertEqual(snapshot.failureReasons, [
            .guestHTTPProbeFailed("failed"),
            .guestBootstrapResultMissing,
        ])
        XCTAssertEqual(snapshot.vmState, .unreachable)
    }

    func testMissingBootstrapResultDoesNotFailWhileLifecycleIsBootstrapping() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vmLifecycle: RuntimeVMLifecycleDocument(
                state: .bootstrapping,
                startedAt: "2026-05-31T00:00:00Z",
                updatedAt: "2026-05-31T00:00:01Z",
                deadlineAt: "2026-05-31T00:10:00Z"
            ),
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            guestBootstrapAssessment: .missing
        ))

        XCTAssertEqual(snapshot.vmErrors, [.guestHTTP(RuntimeHTTPStatusText.bootstrapPending)])
        XCTAssertEqual(snapshot.failureReasons, [.guestHTTP(RuntimeHTTPStatusText.bootstrapPending)])
        XCTAssertEqual(snapshot.vmState, .starting)
    }

    func testUnavailableBootstrapResultIsObservableWhenGuestHTTPFails() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestHTTP: "failed",
            guestBootstrapAssessment: .unavailable("permission denied")
        ))

        XCTAssertEqual(snapshot.vmErrors, [
            .guestHTTPProbeFailed("failed"),
            .guestBootstrapResultUnavailable,
        ])
        XCTAssertEqual(snapshot.failureReasons, [
            .guestHTTPProbeFailed("failed"),
            .guestBootstrapResultUnavailable,
        ])
        XCTAssertEqual(snapshot.vmState, .unreachable)
    }

    func testStaleGuestRuntimeStateProducesTypedReason() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestRuntimeState: .stale
        ))

        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.failureReasons, [.guestRuntimeStateStale])
        XCTAssertEqual(snapshot.vmState, .stale)
        XCTAssertEqual(snapshot.vmErrors, [.runtimeStateStale])
    }

    func testMissingGuestRuntimeStateIsObservableSeparatelyFromGuestHTTP() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            guestRuntimeState: .missing
        ))

        XCTAssertEqual(snapshot.vmState, .unreachable)
        XCTAssertEqual(snapshot.vmErrors, [.runtimeStateMissing])
        XCTAssertEqual(snapshot.failureReasons, [.guestRuntimeStateMissing])
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
        XCTAssertEqual(snapshot.failureReasons, [
            .vmLaunchFailed("virtualization"),
            .vmDiskAttachmentInvalid,
            .guestFilesystemReadOnly,
            .guestDiskIO,
        ])
        XCTAssertEqual(snapshot.failureReasons.map(\.rawValue), [
            "vm-launch-failed-virtualization",
            "vm-disk-attachment-invalid",
            "guest-filesystem-read-only",
            "guest-disk-io-error",
        ])
    }

    func testVMLifecycleTerminalReasonReportsStoragePreservingVMError() {
        let snapshot = RuntimeHealthEvaluator.evaluate(healthyInput(
            vmLifecycle: RuntimeVMLifecycleDocument(
                state: .failed,
                startedAt: "2026-05-31T00:00:00Z",
                updatedAt: "2026-05-31T00:00:05Z",
                terminalReason: .diskAttachmentInvalid
            )
        ))

        XCTAssertEqual(snapshot.vmState, .failed)
        XCTAssertEqual(snapshot.vmErrors, [.diskAttachmentInvalid])
        XCTAssertEqual(snapshot.failureReasons, [.vmDiskAttachmentInvalid])
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
        guestRuntimeState: RuntimeGuestRuntimeStateInput? = nil,
        vmIP: String? = "192.168.64.2",
        proxyPort: Int = 80,
        hostProxyHTTP: String = "200",
        guestHTTP: String = "200",
        redisUIHTTP: String = "200",
        swaggerUIHTTP: String = "200",
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
        containerObservationInput: RuntimeObservationInput<RuntimeContainerObservation>? = nil,
        vitalDBObservationInput: RuntimeObservationInput<VitalDBObservationDocument>? = nil,
        reportedVMErrors: [RuntimeVMError] = [],
        proxyPortFailureReasons: [RuntimeFailureReason] = [],
        guestBootstrapAssessment: GuestBootstrapAssessment = .noFailure
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
            guestRuntimeState: guestRuntimeState ?? .fresh(
                vmIP: vmIP,
                guestHTTP: guestHTTPInput(guestHTTP)
            ),
            proxyPort: proxyPort,
            proxyPortReadState: .loaded(proxyPort),
            hostProxyHTTP: hostProxyHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            containerObservation: containerObservationInput
                ?? containerObservation.map(RuntimeObservationInput.loaded)
                ?? .notReported,
            vitalDBObservation: vitalDBObservationInput
                ?? vitalDBObservation.map(RuntimeObservationInput.loaded)
                ?? .notReported,
            reportedVMErrors: reportedVMErrors,
            proxyPortFailureReasons: proxyPortFailureReasons,
            guestBootstrapAssessment: guestBootstrapAssessment
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
