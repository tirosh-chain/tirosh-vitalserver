import Application
import Contracts
import Domain
import XCTest

final class EvaluateRuntimeHealthUseCaseTests: XCTestCase {
    func testSnapshotIsEvaluatedFromExplicitHealthObservation() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation())

        XCTAssertEqual(snapshot.vmState, .running)
        XCTAssertEqual(snapshot.failureReasons, [])
        XCTAssertEqual(snapshot.vmIP, "192.168.64.2")
        XCTAssertEqual(snapshot.proxyPort, 80)
    }

    func testObservationMapsSkippedProxyHTTPReadsFromMissingProxyPortInUseCase() {
        let observation = EvaluateRuntimeHealthUseCase().observation(from: healthReads(
            proxyPortReadState: .missing("proxy port not configured"),
            hostProxyHTTP: nil,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            recorderIngressStatus: nil
        ))

        XCTAssertNil(observation.proxyPort)
        XCTAssertEqual(observation.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(observation.redisUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(observation.swaggerUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
    }

    func testObservationPrefersGuestControlReadinessOverRuntimeStateReadFailure() {
        let observation = EvaluateRuntimeHealthUseCase().observation(from: healthReads(
            guestControlReadiness: .loaded(
                vmIP: "192.168.64.44",
                readiness: RuntimeGuestControlReadiness(status: "ready")
            )
        ))

        XCTAssertEqual(
            observation.guestReadiness,
            .reported(vmIP: "192.168.64.44", guestHTTP: .reportedStatus("200"))
        )
        XCTAssertFalse(observation.configurationFailureReasons.contains(.guestRuntimeStateLoadFailed("runtime-state_unreadable")))
        XCTAssertEqual(RuntimeHealthEvaluator.evaluate(RuntimeHealthInput(
            vmExecutable: observation.vmExecutable,
            proxyExecutable: observation.proxyExecutable,
            rootfsBase: observation.rootfsBase,
            vmDisk: observation.vmDisk,
            vmService: observation.vmService,
            proxyService: observation.proxyService,
            watchdogService: observation.watchdogService,
            vmLifecycle: observation.vmLifecycle,
            guestReadiness: observation.guestReadiness,
            proxyPort: observation.proxyPort,
            proxyPortReadState: observation.proxyPortReadState,
            hostProxyHTTP: observation.hostProxyHTTP,
            redisUIHTTP: observation.redisUIHTTP,
            swaggerUIHTTP: observation.swaggerUIHTTP,
            guestServiceStatuses: observation.guestServiceStatuses,
            vitalDBObservation: observation.vitalDBObservation,
            reportedVMErrors: observation.reportedVMErrors,
            configurationFailureReasons: [],
            proxyPortFailureReasons: [],
            guestBootstrapAssessment: .noFailure
        )).guestHTTP, "200")
    }

    func testObservationPreservesGuestControlReadinessDependencyFailure() {
        let observation = EvaluateRuntimeHealthUseCase().observation(from: healthReads(
            guestControlReadiness: .loaded(
                vmIP: "192.168.64.44",
                readiness: RuntimeGuestControlReadiness(
                    status: "unavailable",
                    dependencies: [
                        RuntimeGuestControlReadinessDependency(
                            name: "operationRepository",
                            role: "required",
                            state: "failed",
                            kind: "postgresCommandFailed",
                            message: "postgres command failed during readiness"
                        )
                    ]
                )
            )
        ))

        XCTAssertEqual(
            observation.guestReadiness,
            .reported(
                vmIP: "192.168.64.44",
                guestHTTP: .probeFailed(
                    "unavailable:operationRepository:failed:postgresCommandFailed:"
                    + "postgres command failed during readiness"
                )
            )
        )
    }

    func testBootstrapResultFromDifferentBootDoesNotCreateVMFailure() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation(
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            vmLifecycle: runtimeLifecycle(bootID: "current-boot"),
            guestBootstrapResult: .loaded(bootstrapResult(
                status: .failed,
                bootID: "old-boot",
                reasonCodes: [.guestBootstrapMissingRuntimePackages]
            ))
        ))

        XCTAssertFalse(snapshot.failureReasons.contains(RuntimeFailureReason.guestBootstrapMissingRuntimePackages))
        XCTAssertTrue(snapshot.failureReasons.contains(RuntimeFailureReason.guestHTTP(RuntimeHTTPStatusText.bootstrapPending)))
    }

    func testFreshBootstrapFailureIsEvaluatedByUseCaseNotAdapter() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation(
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            vmLifecycle: runtimeLifecycle(bootID: "current-boot"),
            guestBootstrapResult: .loaded(bootstrapResult(
                status: .failed,
                bootID: "current-boot",
                reasonCodes: [.guestBootstrapMissingRuntimePackages]
            ))
        ))

        XCTAssertTrue(snapshot.failureReasons.contains(RuntimeFailureReason.guestBootstrapMissingRuntimePackages))
        XCTAssertTrue(snapshot.vmErrors.contains(RuntimeVMError.guestBootstrapMissingRuntimePackages))
    }

    func testFreshBootstrapDockerRuntimeFailureIsEvaluatedByUseCaseNotAdapter() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation(
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            vmLifecycle: runtimeLifecycle(bootID: "current-boot"),
            guestBootstrapResult: .loaded(bootstrapResult(
                status: .failed,
                bootID: "current-boot",
                reasonCodes: [.guestBootstrapDockerRuntimeFailed]
            ))
        ))

        XCTAssertTrue(snapshot.failureReasons.contains(RuntimeFailureReason.guestBootstrapDockerRuntimeFailed))
        XCTAssertTrue(snapshot.vmErrors.contains(RuntimeVMError.guestBootstrapDockerRuntimeFailed))
    }

    func testObservationKeepsRuntimeStateLoadFailureOutOfCurrentHealthWhenGuestControlIsNotReported() {
        let useCase = EvaluateRuntimeHealthUseCase()
        let observation = useCase.observation(from: healthReads())

        XCTAssertEqual(observation.guestReadiness, RuntimeGuestReadinessInput.notReported)
        XCTAssertFalse(observation.configurationFailureReasons.contains(
            RuntimeFailureReason.guestRuntimeStateLoadFailed("runtime-state_unreadable")
        ))
    }

    func testObservationKeepsRuntimeStateMetadataReadFailureOutOfCurrentHealth() {
        let useCase = EvaluateRuntimeHealthUseCase()
        let observation = useCase.observation(from: healthReads())

        XCTAssertEqual(observation.guestReadiness, RuntimeGuestReadinessInput.notReported)
        XCTAssertFalse(observation.configurationFailureReasons.contains(
            .guestRuntimeStateMetadataReadFailed("stat_permission_denied")
        ))
    }

    func testObservationDoesNotCreateCurrentHealthStateFromRuntimeStatePayload() {
        let useCase = EvaluateRuntimeHealthUseCase()
        let observation = useCase.observation(from: healthReads(
            vitalDBObservation: .notReported
        ))

        let snapshot = useCase.snapshot(observation: observation)

        XCTAssertEqual(observation.guestReadiness, .notReported)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertFalse(snapshot.failureReasons.contains(.guestRuntimeStateMissing))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestRuntimeStateStale))
        XCTAssertEqual(observation.vitalDBObservation, .notReported)
        XCTAssertFalse(snapshot.failureReasons.contains {
            if case .vitalDBAnomaly = $0 {
                return true
            }
            return false
        })
    }
}

private func observation(
    guestHTTP: String = "200",
    vmLifecycle: RuntimeVMLifecycleDocument? = runtimeLifecycle(bootID: "current-boot"),
    guestBootstrapResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> = .missing
) -> RuntimeHealthObservation {
    RuntimeHealthObservation(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmLifecycle: vmLifecycle,
        guestReadiness: .reported(
            vmIP: "192.168.64.2",
            guestHTTP: guestHTTPInput(guestHTTP)
        ),
        proxyPort: 80,
        proxyPortReadState: .loaded(80),
        hostProxyHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        vitalDBObservation: .notReported,
        reportedVMErrors: [],
        configurationFailureReasons: [],
        proxyPortFailureReasons: [],
        guestBootstrapResult: guestBootstrapResult,
        observedAt: date("2026-05-21T12:35:00Z"),
        guestBootstrapFreshnessGraceSeconds: 60
    )
}

private func healthReads(
    guestControlReadiness: RuntimeGuestControlReadinessRead = .notReported,
    proxyPortReadState: RuntimeProxyPortReadState = .loaded(80),
    hostProxyHTTP: String? = "200",
    redisUIHTTP: String? = "200",
    swaggerUIHTTP: String? = "200",
    recorderIngressStatus: RuntimeRecorderIngressStatusReadResult? = nil,
    vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument> = .notReported
) -> RuntimeHealthObservationReads {
    RuntimeHealthObservationReads(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmLifecycleLoadResult: .missing,
        guestControlReadiness: guestControlReadiness,
        proxyPortReadState: proxyPortReadState,
        hostProxyHTTP: hostProxyHTTP.map(RuntimeHTTPProbeResult.reportedStatus),
        redisUIHTTP: redisUIHTTP.map(RuntimeHTTPProbeResult.reportedStatus),
        swaggerUIHTTP: swaggerUIHTTP.map(RuntimeHTTPProbeResult.reportedStatus),
        recorderIngressStatus: recorderIngressStatus,
        vitalDBObservation: vitalDBObservation,
        containerLogsMetadata: RuntimeContainerLogsMetadata(present: false, bytes: nil, updatedAt: nil, error: nil),
        proxyListenerObservation: nil,
        guestBootstrapResult: .missing,
        observedAt: date("2026-05-21T12:35:00Z"),
        guestBootstrapFreshnessGraceSeconds: 60
    )
}

private func bootstrapResult(
    status: GuestBootstrapStatus,
    bootID: String?,
    reasonCodes: [RuntimeFailureReason]?
) -> GuestBootstrapResultDocument {
    GuestBootstrapResultDocument(
        schemaVersion: 2,
        bootID: bootID,
        operation: .unknown("bootstrap"),
        status: status,
        message: nil,
        reasonCodes: reasonCodes,
        updatedAt: "2026-05-21T12:34:57Z"
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

private func runtimeLifecycle(bootID: String?) -> RuntimeVMLifecycleDocument {
    RuntimeVMLifecycleDocument(
        state: .running,
        bootID: bootID,
        startedAt: "2026-05-21T12:34:00Z",
        updatedAt: "2026-05-21T12:35:00Z"
    )
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
